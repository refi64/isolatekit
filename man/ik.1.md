# ik -- Create isolated development environments

## SYNOPSIS

**ik** [options...] command

## DESCRIPTION

IsolateKit is a tool that lets you easily create isolated development environments.
For more information, see isolatekit(7).

## COMMON OPTIONS

The following options are understood by all commands:

**-h, --help**

> Show a help screen.

**-R, --resolve**

> Any relative **file:** unit paths will be resolved relative to the given directory
instead of the current directory.

## TARGET COMMANDS

**target set** [target]

> Set the units used by a target. You may either add units using **--add** or remove units
using **--remove**. If the target does not exist, you may only use **--add**, and the
first unit added *must* be a base unit. All the other units passed must be
builder units. The **--bind-ro** and **--bind-rw** options are ignored in this form.

**target run** [target]

> Run a target. If **--add** and/or **--remove** are passed, the units described by those
commands will be added or removed prior to running the target. Passing **null** as the
target name will simply run the units passed to **--add** inside a temporary target that
will be removed once the command exits.

The following options are understood by the above two commands:

**-a, --add**

> A comma-separated list of unit paths to add to the target before executing the
command. If running on either a nonexistent target or the null target, then the first
unit must be a base, and all others must be builder. Otherwise, they all must be
builders.

**-r, --remove**

> A comma-separated list of unit paths to remove from the target before executing the
command. You cannot remove the base unit from a target. It is invalid to use this on
nonexistent targets or the null target.

**-b, --bind-ro**

> A comma-separated list of read-only bind mounts to add to the target when running it.
The format of each bind mount is *local-path:target-path*, where *local-path* is the host
operating sytem path, and *target-path* is the target mountpoint inside of the target.
Any colons in either path may be escaped by prefixing the colon with a backslash.

**-B, --bind-rw**

> Same as above, except the bind mount is read-write instead of read-only.

## INFORMATION COMMANDS

**info target** [target]

**info unit** [unit]

> Show information on the given targets or units.

**list all**

**list targets**

**list units**

> List everything, targets, or units, respectively.

The following options are understood by the above two commands:

**-t, --terse**

> Show terse output.

## TARGET AND UNIT COMMANDS

**update** [units...]

> Checks for any updates for the given units. If no units are passed, then all the units
will be checked for updates.

**remove targets** [targets...]

**remove units** [units...]

> Remove the given targets or units.

## SEE ALSO

isolatekit.index(7)
