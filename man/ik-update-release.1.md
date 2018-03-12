# ik-update-release -- Helper for updating IsolateKit unit script releases

## SYNOPSIS

**ik-update-release** [files...]

## DESCRIPTION

**ik-update-release** is a helper script that updates the releases in IsolateKit unit
scripts. As mentioned in isolatekit.rc(5), releases are ISO 8061 dates, containing
the 4-digit year, month, day, hour, minute, and second, respectively.

When called with no arguments, **ik-update-release** will print the current time in the
proper format.

When called with a list of file arguments, **ik-update-release** will search for the
rel= variable assignment in each file and replace it with the properly-formatted
current time.
