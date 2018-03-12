# isolatekit.rc -- IsolateKit unit syntax

## SYNOPSIS

*unit*.rc

## DESCRIPTION

Unit files in IsolateKit are simply shell scripts written for the rc(1) shell. They
define variables regarding the unit, as well as functions that are run to set up the
unit.

## SYNTAX

Te variant of rc used by IsolateKit is close in spirit to the original Plan 9 rc,
with a few minor changes. Therefore, you can mostly use the
[original rc manual](http://doc.cat-v.org/plan_9/4th_edition/papers/rc), with some
minor exceptions. These are documented in rc(1) but repeated here for clarity:

- **if not** has been replaced with **else**.
- The $" operator is now the $^ operator.

## UNITS

There are two types of units:

**base units**

> These units are distro bases. They will download and create a minimal OS image.
For instance, the alpine unit is a base unit.

**builder units**

> These units extend/add functionality on top of base units. For instance, the alpine/sdk
unit extends the alpine unit to add the alpine-sdk package.

## VARIABLES

Both unit types must define the following variables:

**name**

> A unique name for the unit.

**type**

> The type of the unit; either *base* or *builder*.

**rel**

> The release version of the unit. This is an ISO 8061-formatted date, in UTC time,
containing:

> - 4-digit year (e.g. 2000)
- A dash.
- 2-digit, 1-indexed month (e.g. 01 for January)
- A dash.
- 2-digit, 1-indexed day (e.g. 11 for the 11th)
- The letter T.
- 2-digit hour.
- A colon.
- 2-digit minute.
- A colon.
- 2-digit second.

> Example: *2018-03-09T22:08:07*. This value can be retrieved and/or updated via
ik-update-release(1).

In addition, the following variables are optional:

**props**

> A list of words, each defining a property that may be passed to the unit file on the
ik(1) command line. The value passed to a prop can be retrieved from within the
functions in the unit file using the variable **prop_NAME**. As props are only assigned
*after* the unit file is loaded but before any functions are called, default values
may be given by assigning to the prop variables in the top-level script code.

Builder units must also define the following variable:

**deps**

> A list of units that the builder depends on. The first *must* be a base unit.

## FUNCTIONS

Base units must define the following functions:

**create**

> Called from the host operating system to create a unit. The following vaiables are
already defined inside this function:

> - **$target**

> > The target directory where the unit operating system data should be placed.

**setup**

> Called from inside the isolate to install packages/set anything else up.

Builder units must define the following functions:

**run**

> Called from inside the isolate to install packages or set anything up that should be
for this unit.

## EXAMPLES

See **units/alpine.rc** and **units/alpine/sdk.rc** for two simple examples of a base unit
and a builder unit, respectively.

## SEE ALSO

isolatekit.index(7), isolatekit(7)
