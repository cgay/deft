module: deft-core
synopsis:
author: Bruce Mitchener, Jr.
copyright: See LICENSE file in this distribution.

define variable *config* :: <string-table> = load-deft-config();

define function parse-config-file
    (filename :: <string>)
 => (config :: <string-table>)
  let config-file = as(<file-locator>, filename);
  if (file-exists?(config-file))
    with-open-file (stream = config-file, direction: #"input")
      block ()
        parse-json(stream)
      exception (ex :: <json-error>)
        format-err("WARNING: Parsing config file '%s' failed:\n%s\n---\n",
                   filename, ex);
        make(<string-table>)
      end
    end
  else
    make(<string-table>)
  end
end function;

// Merge two configs, with config2 overriding values from config1.
define function merge-config
    (config1 :: <string-table>,
     config2 :: <string-table>)
 => (merged-config :: <string-table>)
  let merged-config = make(<string-table>);
  for (value keyed-by key in config1)
    merged-config[key] := value;
  end for;
  for (value keyed-by key in config2)
    merged-config[key] := value;
  end for;
  merged-config
end function;

define function load-deft-config () => (config :: <string-table>)
  let project-config = parse-config-file("deft-package.json");
  let local-config = parse-config-file("deft-package-local.json");
  let merged-config = merge-config(project-config, local-config);
  if (empty?(merged-config))
    format-err("WARNING: No config files found for project.\n");
  end if;
  merged-config
end function;

define function deft-config () => (config :: <string-table>)
  *config*
end function;

define command show deft config ($deft-commands)
  help "Show the entire Deft configuration.";
  implementation
    begin
      let stream = make(<string-stream>, direction: #"output");
      encode-json(stream, deft-config());
      format-out("%s\n", stream-contents(stream));
    end;
end;
