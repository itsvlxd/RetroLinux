import os
import subprocess

BUS_NAME       = "org.bluez.obex"
AGENT_IFACE    = "org.bluez.obex.Agent1"
PROPS_IFACE    = "org.freedesktop.DBus.Properties"
TRANSFER_IFACE = "org.bluez.obex.Transfer1"
SESSION_IFACE  = "org.bluez.obex.Session1"


def calc_notif_id(mac):
    mac_clean = mac.replace(":", "")
    if len(mac_clean) != 12:
        return 48923
    notif_id = int(mac_clean, 16) % 1000000
    if notif_id < 10000:
        notif_id += 10000
    return notif_id


def get_cancel_flag_path(mac, prefix="receive"):
    notif_id = calc_notif_id(mac)
    return f"/tmp/.bt_{prefix}_{notif_id}_cancel"


def clean_cancel_flag(mac, prefix="receive"):
    flag = get_cancel_flag_path(mac, prefix)
    if os.path.exists(flag):
        os.remove(flag)
        return True
    return False


def set_cancel_flag(mac, prefix="receive"):
    flag = get_cancel_flag_path(mac, prefix)
    open(flag, "w").close()


def run_shell_cmd(shell_script, *args, env=None, capture=False):
    cmd_env = {**os.environ}
    if env:
        cmd_env.update(env)

    if capture:
        return subprocess.run(
            [shell_script] + list(args),
            capture_output=True, text=True,
            env=cmd_env
        )
    else:
        return subprocess.call(
            [shell_script] + list(args),
            env=cmd_env
        )
