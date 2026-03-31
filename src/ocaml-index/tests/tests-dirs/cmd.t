  $ ocaml-index aggregate
  $ ocaml-index aggregate --debug
  [debug] Debug log is enabled

  $ ocaml-index --help
  ocaml-index [COMMAND] [-verbose] <file1> [<file2>] ... -o <output>
    --verbose Output more information
    --debug Output debugging information
    -o Set output file name. Note that sub-indexes paths remains relative to the current directory.
    --root Set the root path for all relative locations
    --rewrite-root Rewrite locations paths using the provided root
    --store-shapes Aggregate input-indexes shapes and store them in the new index
    -I An extra directory to add to the load path
    -H An extra hidden directory to add to the load path
    --no-cmt-load-path Do not initialize the load path with the paths found in the first input cmt file
    --cache-size Set LRU cache size. Will bound memory usage in read-heavy scenarios.
    -help  Display this list of options
    --help  Display this list of options
