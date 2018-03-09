# IsolateKit

## What is IsolateKit?

IsolateKit is a lightweight Docker/rkt/containerization alternative, designed
specifically for creating reproducible development environment, vs Docker and rkt's
general-purpose usage.

## What's wrong with Docker?

Docker is great, but it wasn't designed for containers. For instance:

- The only way to use multiple images at once is through multi-stage builds, which,
  though great, make it difficult to install multiple dependencies. Have a project that
  needs to be built on CentOS and depends on devtoolset-7, Python, and Ruby in one
  build stage? Tough luck; you'll have to pick one image and then install everything
  else onto it manually.
- It's a bit unintuitive to run an image directly using a temporary container. Want to
  run the Alpine image just once? Try `docker run -t -i --rm alpine ash`. Ouch.
- The new mount syntax makes bind mounts (which is what you'll almost always be using
  for building binaries) painful: `--mount type=bind,source=xyz,destination=xyz`.
- You can only depend on already-built images, not unbuilt Dockerfiles. This makes
  creating multiple images harder than it needs to be.

## What's wrong with rkt?

- acbuild combines everything wrong with state machines and everything wrong with
  declarative build formats into one.
- AppC is dead, and rkt doesn't support OCI yet. Oh, as as a result of OCI,
  acbuild is unmaintained.

## What's wrong with Rootbox?

[Rootbox](https://project-rootbox.github.io), IsolateKit's predecessor, was great, but
it had a lot of problems:

- I wrote it in Bash. Seemed like a good idea at the time, ended up being an epic
  disaster.
- There was no concept of proper dependency management, so creating new boxes required
  running all of the factories it depended on...even if there was no need.
- It was hard-coded to Alpine Linux and wasn't designed in a way to make it easily
  extensible. Alpine is great for building static binaries, but you can't use it to
  build other things like AppImages.

## IsolateKit Highlights

- Lightweight. GLib is the only runtime dependency, and Vala is the only built-time
  dependency.
- Built on top of systemd-nspawn.
- Designed to make generating environments from source scripts insanely easy. IsolateKit
  in its current state isn't really designed around using binary images.

## Terminology

- **Isolate:** A combination of multiple file system layers that can be run. The
  IsolateKit equivalent of a Docker container.
- **Unit:** Basically, the IsolateKit equivalent of a Docker image. Units are a single
  file system that will be layered on top of others to generate a full isolate.
- **Target:** A target tells IsolateKit how to run an isolate. It contains both a list
  of units to run and a working directory where changes should be placed.

## Usage

TODO

```
$ ik target set

$ ik target run

$ ik update

$ ik list all
$ ik list targets
$ ik list units

$ ik remove targets a b
$ ik remove units d e f
```
