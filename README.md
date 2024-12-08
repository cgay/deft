# Deft

[![tests](https://github.com/dylan-lang/deft/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/dylan-lang/deft/.github/workflows/build-and-test.yml)
[![GitHub issues](https://img.shields.io/github/issues/dylan-lang/deft?color=blue)](https://github.com/dylan-lang/deft/issues)
[![Matrix](https://img.shields.io/matrix/dylan-lang-general:matrix.org?color=blue&label=Chat%20on%20Matrix&server_fqdn=matrix.org)](https://app.element.io/#/room/#dylan-language:matrix.org)

* Manage project dependencies
* No more editing registry files
* No more Git submodules
* Build/test from anywhere in your workspace
* Create boilerplate for new projects

Deft simplifies the management of Dylan workspaces and packages and
provides a simplified interface to the Open Dylan compiler for building and
(soon) testing and generating documentation. It eliminates the need to manage
library locations (registries) by hand and the need to use Git submodules to
track dependencies.

    $ deft new application hello
    Downloaded pacman-catalog@master to /tmp/dylan/_packages/pacman-catalog/master/src/
    Created library hello.
    Created library hello-test-suite.
    Created library hello-app.
    Downloaded strings@1.1.0 to /tmp/hello/_packages/strings/1.1.0/src/
    Downloaded command-line-parser@3.1.1 to /tmp/hello/_packages/command-line-parser/3.1.1/src/
    Downloaded json@1.0.0 to /tmp/hello/_packages/json/1.0.0/src/
    Downloaded testworks@2.3.1 to /tmp/hello/_packages/testworks/2.3.1/src/
    Updated 18 files in /tmp/hello/registry/.

    $ cd hello

    $ deft build --all
    Open Dylan 2023.1
    Build of 'hello-test-suite' completed
    Build of 'hello-app' completed
    Build of 'hello' completed

    $ _build/bin/hello-app
    Hello world!


A key part of this tool is the package manager (pacman) and its catalog of
packages, the [pacman-catalog](https://github.com/dylan-lang/pacman-catalog)
repository. For any package to be downloadable it must have an entry in the
catalog.

Full documentation is
[here](https://opendylan.org/package/deft).

## Bugs

If you have a feature request, think something should be designed differently, or find
bugs, [file a bug report](https://github.com/dylan-lang/deft/issues).
