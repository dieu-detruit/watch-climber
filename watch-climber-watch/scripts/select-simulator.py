import json, sys
available = json.load(sys.stdin)['devices']
for runtime, devices in available.items():
    if 'watchOS' in runtime:
        for device in devices:
            if device.get('isAvailable'):
                print(device['udid'])
                sys.exit(0)
raise SystemExit('No available watchOS simulator; install a watchOS runtime in this Xcode image.')
