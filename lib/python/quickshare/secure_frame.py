"""Post-handshake SecureMessage encrypt/decrypt layer.

Plaintext DeviceToDeviceMessage(seq, frame_bytes) is AES-256-CBC encrypted,
wrapped in HeaderAndBody, then HMAC-SHA256'd (encrypt-then-MAC, over the
full serialized HeaderAndBody) to produce a SecureMessage, per
third_party/ukey2/ukey2/src/main/cpp/src/securegcm/d2d_crypto_ops.cc
(SigncryptPayload) and the securemessage/crypto_ops.cc Sign/Encrypt paths in
https://github.com/google/nearby (that path vendors github.com/google/ukey2
as a submodule).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from quickshare import crypto, debug
from quickshare.proto import device_to_device_messages_pb2 as d2d_pb2
from quickshare.proto import securegcm_pb2
from quickshare.proto import securemessage_pb2

_GCM_TYPE_DEVICE_TO_DEVICE_MESSAGE = 13  # securegcm.Type.DEVICE_TO_DEVICE_MESSAGE


class SecureFrameError(Exception):
    pass


@dataclass
class SecureChannel:
    encrypt_key: bytes
    decrypt_key: bytes
    send_hmac_key: bytes
    recv_hmac_key: bytes
    server_seq: int = field(default=0)

    def _next_server_seq(self) -> int:
        self.server_seq += 1
        return self.server_seq

    def encrypt(self, frame_bytes: bytes) -> bytes:
        """frame_bytes -> serialized SecureMessage, ready to send framed on the wire."""
        d2d_msg = d2d_pb2.DeviceToDeviceMessage(
            message=frame_bytes,
            sequence_number=self._next_server_seq(),
        )
        iv = crypto.random_bytes(16)
        ciphertext = crypto.aes_cbc_encrypt(self.encrypt_key, iv, d2d_msg.SerializeToString())

        header = securemessage_pb2.Header(
            encryption_scheme=securemessage_pb2.AES_256_CBC,
            signature_scheme=securemessage_pb2.HMAC_SHA256,
            iv=iv,
            public_metadata=securegcm_pb2.GcmMetadata(
                type=_GCM_TYPE_DEVICE_TO_DEVICE_MESSAGE,
                version=1,
            ).SerializeToString(),
        )
        header_and_body_bytes = securemessage_pb2.HeaderAndBody(
            header=header,
            body=ciphertext,
        ).SerializeToString()

        signature = crypto.hmac_sha256(self.send_hmac_key, header_and_body_bytes)

        secure_message = securemessage_pb2.SecureMessage(
            header_and_body=header_and_body_bytes,
            signature=signature,
        )
        serialized = secure_message.SerializeToString()
        debug.trace("secure", f"-> SecureMessage seq={d2d_msg.sequence_number} ({len(serialized)} bytes, {len(frame_bytes)} plaintext)")
        return serialized

    def decrypt(self, secure_message_bytes: bytes) -> bytes:
        """serialized SecureMessage -> inner frame_bytes. Verifies HMAC before decrypting."""
        secure_message = securemessage_pb2.SecureMessage()
        secure_message.ParseFromString(secure_message_bytes)

        if not crypto.hmac_verify(
            self.recv_hmac_key, secure_message.header_and_body, secure_message.signature
        ):
            if debug.enabled(debug.TRACE):
                debug.log_hmac_mismatch(
                    self.recv_hmac_key,
                    secure_message.header_and_body,
                    secure_message.signature,
                    crypto.hmac_sha256(self.recv_hmac_key, secure_message.header_and_body),
                )
            raise SecureFrameError("HMAC verification failed")

        header_and_body = securemessage_pb2.HeaderAndBody()
        header_and_body.ParseFromString(secure_message.header_and_body)

        plaintext = crypto.aes_cbc_decrypt(
            self.decrypt_key, header_and_body.header.iv, header_and_body.body
        )
        d2d_msg = d2d_pb2.DeviceToDeviceMessage()
        d2d_msg.ParseFromString(plaintext)
        debug.trace(
            "secure",
            f"<- SecureMessage seq={d2d_msg.sequence_number} "
            f"({len(secure_message_bytes)} bytes, {len(d2d_msg.message)} plaintext)",
        )
        return d2d_msg.message
