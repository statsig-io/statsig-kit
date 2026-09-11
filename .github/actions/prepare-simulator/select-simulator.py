#!/usr/bin/env python3
"""Pick a simulator runtime and device type that are compatible with each other.

`simctl list devicetypes` is global, so a device type can be listed while no
installed runtime supports it -- `simctl create` then fails. Only the
`supportedDeviceTypes` array on each runtime says which pairs actually work.

Prints one TSV line on success:
    runtime_id, runtime_name, device_type_id, device_type_name, existing_udid
"""

import json
import re
import subprocess
import sys


def simctl(what):
    out = subprocess.check_output(["xcrun", "simctl", "list", what, "--json"])
    return json.loads(out)


def main():
    runtime_prefix, device_pattern = sys.argv[1], sys.argv[2]
    pattern = re.compile(device_pattern)

    runtimes = [
        r
        for r in simctl("runtimes")["runtimes"]
        if r.get("isAvailable") and r["name"].startswith(runtime_prefix + " ")
    ]
    devices = simctl("devices")["devices"]

    for runtime in runtimes:
        for device_type in runtime.get("supportedDeviceTypes", []):
            if not pattern.match(device_type["name"]):
                continue
            existing = next(
                (
                    d["udid"]
                    for d in devices.get(runtime["identifier"], [])
                    if d.get("isAvailable")
                    and d.get("deviceTypeIdentifier") == device_type["identifier"]
                ),
                "",
            )
            print(
                "\t".join(
                    [
                        runtime["identifier"],
                        runtime["name"],
                        device_type["identifier"],
                        device_type["name"],
                        existing,
                    ]
                )
            )
            return 0

    if not runtimes:
        print(f"No available {runtime_prefix} simulator runtime found.", file=sys.stderr)
    else:
        print(
            f"No available {runtime_prefix} runtime supports a device type matching "
            f"{device_pattern!r}.",
            file=sys.stderr,
        )
        for runtime in runtimes:
            supported = ", ".join(
                dt["name"] for dt in runtime.get("supportedDeviceTypes", [])
            )
            print(
                f"  {runtime['name']} ({runtime['identifier']}) supports: "
                f"{supported or '<none>'}",
                file=sys.stderr,
            )
    return 1


if __name__ == "__main__":
    sys.exit(main())
