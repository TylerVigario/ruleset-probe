# Print the run script of the Decide step in a release.yml.
# Usage: python3 -I extract-decide.py <release.yml>
import sys

import yaml

wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["decide"]["steps"]
(step,) = [s for s in steps if s.get("name") == "Decide"]
sys.stdout.write(step["run"])
