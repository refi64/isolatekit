# isolatekit.tutorial -- A brief tutorial on using IsolateKit

## INTRODUCTION

IsolateKit is a tool that lets you easily create reproducible development environments.
This man page is a tutorial to quickly get you up-to-speed.

## BASICS

Read isolatekit(7) first. That will explain some basic terminology and concepts behind
using IsolateKit.

As an example, let's say you want to create a build environment to statically compile
aria2c binaries. You can create a target named aria2c-build, that contains the units
alpine and alpine/sdk. (Alpine is great for building static binaries). Then, when you
want to work in your build environment, you just "run" the target.

## COMMAND LINE USAGE

The ik(1) tool is the main tool used for working with IsolateKit. Re-iterating the above
use case of an aria2c target, you could try something like this:

```bash
# Create a target named aria2c, containing the alpine and alpine/sdk units.
# -a/--add adds units to a target, creating it if it doesn't already exist.
# Note that the base unit (ik:alpine) must ALWAYS come first.
$ ik target set aria2c -a ik:alpine,ik:alpine/sdk
# Actually, maybe we don't want the alpine/sdk unit.
# -r/--remove removes units from a target.
$ ik target set aria2c -r ik:alpine/sdk
# Wait, I take that back.
$ ik target set aria2c -a ik:alpine/sdk
# Now run the target. This will open up a shell inside the target.
$ ik target run aria2c
# Maybe we want to run it without alpine/sdk.
# The -a/--add and -r/--remove flags can be passed to 'target run', too.
$ ik target run aria2c -r ik:alpine/sdk
# Run the target, but pass a read-only bind mount, mounting $PWD as /workspace.
$ ik target run aria2c -b $PWD:/workspace
# Same as above, but with a read-write bind mount.
$ ik target run aria2c -B $PWD:/workspace
# List info about the target we just created.
$ ik info target aria2c
# List all the targets and units we've downloaded.
$ ik list all
$ ik list targets
# Delete the target.
$ ik remove aria2c

# If you want to play around with units without actually creating a target, just
# run the 'null' target:
$ ik run null -a ik:alpine,ik:alpine/sdk
```

## CREATING UNIT SCRIPTS

See isolatekit.rc(5).

## SEE ALSO

isolatekit.index(7), isolatekit(7), ik(1)
