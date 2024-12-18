module: %workspaces
synopsis: Manage developer workspaces

// A workspace is just a directory with this layout:
//   _build/...     -- auto-generated by `dylan-compiler -build ...`
//   lib1/dylan-package.json
//   lib1/...
//   lib2/dylan-package.json
//   lib2/...
//   registry/...   -- auto-generated by `deft update`
//   workspace.json -- workspace file with at least "{}"
//
// Generally the top-level workspace directory itself is not under version
// control.

// TODO:
// * Display the number of registry files updated and the number unchanged.
//   It gives reassuring feedback that something went right when there's no
//   other output.

// The class of errors explicitly signalled by this module.
define class <workspace-error> (<simple-error>)
end class;

define function workspace-error
    (format-string :: <string>, #rest args)
  error(make(<workspace-error>,
             format-string: format-string,
             format-arguments: args));
end function;

define constant $workspace-file-name = "workspace.json";
define constant $dylan-package-file-name = "dylan-package.json";
// TODO: remove support for deprecated pkg.json file in the 1.0 version or once
// all catalog packages are converted, whichever comes first.
define constant $pkg-file-name = "pkg.json";
define constant $default-library-key = "default-library";

// Create a new workspace named `name` under `parent-directory`. If `parent-directory` is
// not supplied use the standard location.
//
// TODO: validate `name`
define function new
    (name :: <string>, #key parent-directory :: false-or(<directory-locator>))
 => (ws :: false-or(<workspace>))
  let dir = parent-directory | fs/working-directory();
  let ws-dir = subdirectory-locator(dir, name);
  let ws-path = file-locator(ws-dir, $workspace-file-name);
  let existing = find-workspace-file(dir);
  if (existing)
    workspace-error("Can't create workspace file %s because it is inside another"
                      " workspace, %s.", ws-path, existing);
  end;
  if (fs/file-exists?(ws-path))
    note("Workspace already exists: %s", ws-path);
  else
    fs/ensure-directories-exist(ws-path);
    fs/with-open-file (stream = ws-path,
                       direction: #"output", if-does-not-exist: #"create",
                       if-exists: #"error")
      format(stream, """
                     # Dylan workspace %=

                     {}

                     """, name);
    end;
    note("Workspace created: %s", ws-path);
  end;
  load-workspace(directory: ws-dir)
end function;

// Update the workspace based on the workspace.json file or signal an error.
define function update
    (#key directory :: <directory-locator> = fs/working-directory(),
          global? :: <bool>)
 => ()
  let ws = load-workspace(directory: directory);
  let cat = pm/catalog();
  dynamic-bind (*package-manager-directory*
                  = if (global?)
                      *package-manager-directory*
                    else
                      subdirectory-locator(workspace-directory(ws),
                                           pm/$package-directory-name)
                    end)
    let (releases, actives) = update-deps(ws, cat);
    let registry = update-registry(ws, cat, releases, actives);
    let no-lid = registry.libraries-with-no-lid;
    if (~empty?(no-lid) & *verbose?*)
      warn("These libraries had no LID file for platform %s:\n  %s",
           os/$platform-name, join(sort!(no-lid), ", "));
    end;

    let reg-dir = subdirectory-locator(registry.root-directory, "registry");
    let num-files = registry.num-files-written;
    if (num-files == 0)
      note("Registry %s is up-to-date.", reg-dir);
    else
      note("Updated %d files in %s.", registry.num-files-written, reg-dir);
    end;
  end;
end function;

// See the section "Workspaces" in the documentation.
define class <workspace> (<object>)
  constant slot workspace-directory :: <directory-locator>,
    required-init-keyword: directory:;
  constant slot workspace-registry :: <registry>,
    required-init-keyword: registry:;
  constant slot workspace-active-packages :: <seq> = #[], // <package>s
    init-keyword: active-packages:;
  constant slot workspace-default-library-name :: false-or(<string>) = #f,
    init-keyword: default-library-name:;
  constant slot multi-package-workspace? :: <bool> = #f,
    init-keyword: multi-package?:;
end class;

define function workspace-registry-directory
    (ws :: <workspace>) => (dir :: <directory-locator>)
  let registry = ws.workspace-registry;
  subdirectory-locator(registry.root-directory, "registry")
end function;

// Loads the workspace definition by looking up from `directory` to find the
// workspace root and loading the workspace.json file. If no workspace.json
// file exists, the workspace is created using the dylan-package.json file (if
// any) and default values. As a last resort `directory` is used as the
// workspace root. Signals `<workspace-error>` if either JSON file is found but
// is invalid.
define function load-workspace
    (#key directory :: <directory-locator> = fs/working-directory())
 => (workspace :: <workspace>)
  let ws-file = find-workspace-file(directory);
  let dp-file = find-dylan-package-file(directory);
  ws-file
    | dp-file
    | workspace-error("Can't find %s or %s. Not inside a workspace?",
                      $workspace-file-name, $dylan-package-file-name);
  let ws-dir = locator-directory(ws-file | dp-file);
  let registry = make(<registry>, root-directory: ws-dir);
  let active-packages = find-active-packages(ws-dir);
  let ws-json = ws-file & load-json-file(ws-file);
  let default-library
    = ws-json & element(ws-json, $default-library-key, default: #f);
  if (~default-library)
    let libs = find-library-names(registry);
    if (~empty?(libs))
      local method match (suffix, lib)
              ends-with?(lib, suffix) & lib
            end;
      // The assumption here is that (for small projects) there's usually one
      // test library that you want to run.
      default-library := (any?(curry(match, "-test-suite-app"), libs)
                            | any?(curry(match, "-test-suite"), libs)
                            | any?(curry(match, "-tests"), libs)
                            | libs[0]);
    end;
  end;
  make(<workspace>,
       active-packages: active-packages,
       directory: ws-dir,
       registry: registry,
       default-library-name: default-library,
       multi-package?: (active-packages.size > 1
                          | (ws-file
                               & dp-file
                               & (ws-file.locator-directory ~= dp-file.locator-directory))))
end function;

define function load-json-file (file :: <file-locator>) => (config :: false-or(<table>))
  fs/with-open-file(stream = file, if-does-not-exist: #f)
    let object = parse-json(stream, strict?: #f, table-class: <istring-table>);
    if (~instance?(object, <table>))
      workspace-error("Invalid JSON file %s, must contain at least {}", file);
    end;
    object
  end
end function;

// Find the workspace directory. The nearest directory containing
// workspace.json always takes precedence. Otherwise the nearest directory
// containing dylan-package.json.
define function find-workspace-directory
    (start :: <directory-locator>) => (dir :: false-or(<directory-locator>))
  let ws-file = find-workspace-file(start);
  (ws-file & ws-file.locator-directory)
    | begin
        let pkg-file = find-dylan-package-file(start);
        pkg-file & pkg-file.locator-directory
      end
end function;

define function find-workspace-file
    (directory :: <directory-locator>) => (file :: false-or(<file-locator>))
  find-file-in-or-above(directory, as(<file-locator>, $workspace-file-name))
end function;

define function find-dylan-package-file
    (directory :: <directory-locator>) => (file :: false-or(<file-locator>))
  find-file-in-or-above(directory, as(<file-locator>, $dylan-package-file-name))
    | find-file-in-or-above(directory, as(<file-locator>, $pkg-file-name))
end function;

define function current-dylan-package
    (directory :: <directory-locator>) => (p :: false-or(pm/<release>))
  let dp-file = find-dylan-package-file(directory);
  dp-file & pm/load-dylan-package-file(dp-file)
end function;

// Return the nearest file or directory with the given `name` in or above
// `directory`. `name` is expected to be a locator with an empty path
// component.
define function find-file-in-or-above
    (directory :: <directory-locator>, name :: <locator>)
 => (file :: false-or(<locator>))
  let want-dir? = instance?(name, <directory-locator>);
  iterate loop (dir = simplify-locator(directory))
    if (dir)
      let file = merge-locators(name, dir);
      if (fs/file-exists?(file)
            & begin
                let type = fs/file-type(file);
                (type == #"directory" & want-dir?)
                  | (type == #"file" & ~want-dir?)
              end)
        file
      else
        loop(dir.locator-directory)
      end
    end
  end
end function;

// Look for dylan-package.json or */dylan-package.json relative to the workspace
// directory and turn it/them into a sequence of `<release>` objects.
define function find-active-packages
    (directory :: <directory-locator>) => (pkgs :: <seq>)
  let subdir-files
    = collecting ()
        for (locator in fs/directory-contents(directory))
          if (instance?(locator, <directory-locator>))
            let dpkg = file-locator(locator, $dylan-package-file-name);
            let pkg = file-locator(locator, $pkg-file-name);
            if (fs/file-exists?(dpkg))
              collect(dpkg);
            elseif (fs/file-exists?(pkg))
              warn("Please rename %s to %s; support for %= will be"
                     " removed soon.", pkg, $dylan-package-file-name, $pkg-file-name);
              collect(pkg);
            end;
          end;
        end for;
      end collecting;
  local method check-file (file, warn-obsolete?)
          if (fs/file-exists?(file))
            if (~empty?(subdir-files))
              warn("Workspace has both a top-level package file (%s) and"
                     " packages in subdirectories (%s). The latter will be ignored.",
                   file, join(map(curry(as, <string>), subdir-files), ", "));
            end;
            if (warn-obsolete?)
              warn("Please rename %s to %s; support for %= will be"
                     " removed soon.", file, $dylan-package-file-name, $pkg-file-name);
            end;
            vector(pm/load-dylan-package-file(file))
          end
        end method;
  check-file(file-locator(directory, $dylan-package-file-name), #f)
    | check-file(file-locator(directory, $pkg-file-name), #t)
    | map(pm/load-dylan-package-file, subdir-files)
end function;

define function active-package-names
    (ws :: <workspace>) => (names :: <seq>)
  map(pm/package-name, ws.workspace-active-packages)
end function;

// These next three should probably have methods on (<workspace>, <package>) too.
define function active-package-directory
    (ws :: <workspace>, pkg-name :: <string>) => (d :: <directory-locator>)
  if (ws.multi-package-workspace?)
    subdirectory-locator(ws.workspace-directory, pkg-name)
  else
    ws.workspace-directory
  end
end function;

define function active-package-file
    (ws :: <workspace>, pkg-name :: <string>) => (f :: <file-locator>)
  let dir = active-package-directory(ws, pkg-name);
  let dpkg = file-locator(dir, $dylan-package-file-name);
  let pkg = file-locator(dir, $pkg-file-name);
  if (fs/file-exists?(pkg) & ~fs/file-exists?(dpkg))
    pkg
  else
    dpkg
  end
end function;

define function active-package?
    (ws :: <workspace>, pkg-name :: <string>) => (_ :: <bool>)
  member?(pkg-name, ws.active-package-names, test: string-equal-ic?)
end function;

// Resolve active package dependencies and install them.
define function update-deps
    (ws :: <workspace>, cat :: pm/<catalog>)
 => (releases :: <seq>, actives :: <istring-table>)
  let (releases, actives) = find-active-package-deps(ws, cat, dev?: #t);
  // Install dependencies to ${DYLAN}/pkg.
  for (release in releases)
    if (~element(actives, release.pm/package-name, default: #f))
      pm/install(release, deps?: #f, force?: #f, actives: actives);
    end;
  end;
  values(releases, actives)
end function;

// Find the transitive dependencies of the active packages in workspace
// `ws`. If `dev?` is true then include dev dependencies in the result.
define function find-active-package-deps
    (ws :: <workspace>, cat :: pm/<catalog>, #key dev?)
 => (releases :: <seq>, actives :: <istring-table>)
  let actives = make(<istring-table>);
  let deps = make(<stretchy-vector>);
  // Dev deps could go into deps, above, but they're kept separate so that
  // pacman can give more specific error messages.
  let dev-deps = make(<stretchy-vector>);
  for (pkg-name in ws.active-package-names)
    let rel = pm/load-dylan-package-file(active-package-file(ws, pkg-name));
    // active-package-names wouldn't include the release if it didn't have a
    // package file.
    assert(rel);
    actives[pkg-name] := rel;
    for (dep in rel.pm/release-dependencies)
      add-new!(deps, dep)
    end;
    if (dev?)
      for (dep in rel.pm/release-dev-dependencies)
        add-new!(dev-deps, dep);
      end;
    end;
  end;
  let deps = as(pm/<dep-vector>, deps);
  let dev-deps = as(pm/<dep-vector>, dev-deps);
  let releases-to-install = pm/resolve-deps(cat, deps, dev-deps, actives);
  values(releases-to-install, actives)
end function;

// Create/update a single registry directory having an entry for each library
// in each active package and all transitive dependencies.  This traverses
// package directories to find .lid files. Note that it assumes that .lid files
// that have no "Platforms:" section are generic, and writes a registry file
// for them (unless they're included in another LID file via the LID: keyword,
// in which case it is assumed they're for inclusion only).
define function update-registry
    (ws :: <workspace>, cat :: pm/<catalog>, releases :: <seq>, actives :: <istring-table>)
 => (r :: <registry>)
  let registry = ws.workspace-registry;
  for (rel in actives)
    update-for-directory(registry, active-package-directory(ws, rel.pm/package-name));
  end;
  for (rel in releases)
    update-for-directory(registry, pm/source-directory(rel));
  end;
  registry
end function;

// Find the names of all libraries defined in the active packages within the
// workspace `ws`.
define function find-active-package-library-names
    (ws :: <workspace>) => (names :: <seq>)
  let names = #[];
  for (package in find-active-packages(ws.workspace-directory))
    let dir = active-package-directory(ws, pm/package-name(package));
    let more-names = find-library-names(dir);
    verbose("Found libraries %= in %s", more-names, dir);
    names := concat(names, more-names);
  end;
  names
end function;
