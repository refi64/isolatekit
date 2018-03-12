# isolatekit -- Guide on IsolateKit basic concepts

## DESCRIPTION

IsolateKit is a tool that lets you easily create isolated development environments.

## TERMINOLOGY

An **isolate** is a runnable "container", for lack of a better analogy. It consists of a
set of layered **units**, each describing one portion of the isolate.

There are two types of units: bases and builders. Base units are a base Linux root,
and builder units "build" on top of that base to add more functionality.

For example, two of the units available for IsolateKit are the alpine and alpine/sdk
units. The former is a base unit that creates a minimal Alpine Linux installation root,
and the latter is a builder unit that installs the alpine-sdk package.

When any of these units are run, the changes they make to the root filesystem are
stored individually as layers, like Docker does. That way, if the alpine/sdk unit is
updated, the alpine unit won't have to be re-run.

**targets** are a combination of an isolate (a set of units) and a working directory
where any changes made to the root filesystem will be saved to. These are the build
environments that can be created with IsolateKit.

All these units are built using **unit scripts**, which are just rc(1) scripts that
create the units. These end in .rc. For more information, see isolatekit.rc(5).

Unit scripts are referenced via **unit paths**, which describe the path to a unit script.


## UNIT PATHS

There are 4 types of unit paths:

**file:**file-path

> A path to a file on the local file system. Example: *file:my-unit.rc*

**git:**git-repo//file-path

> A path to a Git repo, and a file within that repo. If git-repo is looks like a
repository (e.g. myuser/myrepo), then this does the same thing as github:. You can drop
the .rc suffix on file-path.

**github:**git-repo//file-path

> Same as the above, but shorthand for GitHub repos. Again, the the .rc suffix on the file
path can be dropped. Example: *git:kirbyfan64/isolatekit//units/alpine*, or
*git:kirbyfan64/isolatekit//units/alpine.rc*.

**ik:**file-path

> *ik:xyz* is shorthand for *github:kirbyfan64/isolatekit//units/xyz*. This is a shortcut for
using units included with the IsolateKit repository.

## SEE ALSO

isolatekit.index(7), isolatekit.tutorial(7), ik(1)
