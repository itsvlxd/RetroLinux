#!/usr/bin/env python3

import sys
import os
import dbus
from gi.repository import GLib

uid = os.getuid()
os.environ['DBUS_SESSION_BUS_ADDRESS'] = f'unix:path=/run/user/{uid}/bus'

def send_file(mac, file_path):
    if not os.path.exists(file_path):
        print(f"ERR_FILE_NOT_FOUND|{file_path}")
        return 1

    try:
        bus = dbus.SessionBus()

        obj = bus.get_object("org.bluez.obex", "/org/bluez/obex")
        client = dbus.Interface(obj, "org.bluez.obex.Client1")

        session_path = client.CreateSession(
            mac,
            dbus.Dictionary({"Target": dbus.String("00001105-0000-1000-8000-00805f9b34fb")}, signature="sv")
        )
        print(f"Session: {session_path}", file=sys.stderr)

        session_obj = bus.get_object("org.bluez.obex", session_path)
        session = dbus.Interface(session_obj, "org.bluez.obex.Session1")

        transfer_path = session.Push(file_path)
        print(f"Transfer: {transfer_path}", file=sys.stderr)

        transfer_obj = bus.get_object("org.bluez.obex", transfer_path)
        transfer = dbus.Interface(transfer_obj, "org.freedesktop.DBus.Properties")

        def check_status():
            try:
                props = transfer.GetAll("org.bluez.obex.Transfer1")
                status = str(props.get("Status", ""))
                transferred = int(props.get("Transferred", 0))
                print(f"Status: {status}, Transferred: {transferred}", file=sys.stderr)
                if status == "complete":
                    print(f"OK|{file_path}")
                    return False
                elif status == "error":
                    err = str(props.get("Error", "unknown"))
                    print(f"ERR_SEND_FAILED|{err}", file=sys.stderr)
                    return False
            except Exception as e:
                print(f"Check error: {e}", file=sys.stderr)
            return True

        def on_signal(*args, **kwargs):
            try:
                iface = args[0]
                changed = args[1]
                if iface == "org.bluez.obex.Transfer1" and "Status" in changed:
                    status = str(changed["Status"])
                    if status == "complete":
                        print(f"OK|{file_path}")
                        raise SystemExit(0)
                    elif status == "error":
                        print(f"ERR_SEND_FAILED|transfer failed")
                        raise SystemExit(1)
            except SystemExit:
                raise
            except Exception as e:
                print(f"Signal error: {e}", file=sys.stderr)

        bus.add_signal_receiver(on_signal, signal_name="PropertiesChanged", dbus_interface="org.freedesktop.DBus.Properties", path_keyword="path")

        result = [None]
        def poll_status():
            if not check_status():
                raise SystemExit(0)
            return True

        GLib.timeout_add(500, poll_status)

        def timeout_handler():
            print(f"ERR_SEND_FAILED|timeout", file=sys.stderr)
            raise SystemExit(1)

        GLib.timeout_add(60000, timeout_handler)

        mainloop = GLib.MainLoop()
        mainloop.run()
        return 0

    except SystemExit as e:
        return e.code
    except dbus.exceptions.DBusException as e:
        print(f"ERR_SEND_FAILED|{str(e)}")
        return 1
    except Exception as e:
        print(f"ERR_SEND_FAILED|{str(e)}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("ERR_MISSING_ARGS")
        sys.exit(1)

    mac = sys.argv[1]
    file_path = sys.argv[2]
    sys.exit(send_file(mac, file_path))
