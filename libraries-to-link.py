import json
import sys

chainid = 31337
if len(sys.argv) <= 1:
    print("Missing chain id parameter, using 31337")
else:
    chainid = sys.argv[1]

libraries = []
with open(f"broadcast/00_Libraries.s.sol/{chainid}/run-latest.json") as f:
    data = json.load(f)
    libraries = data["libraries"]

cli_option = "--libraries " + " --libraries ".join(libraries)
print(cli_option)
