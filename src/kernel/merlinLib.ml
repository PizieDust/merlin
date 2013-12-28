open Std
open Misc

module Lexer: sig
  type item =
    | Valid of Chunk_parser.token
    | Error of Raw_lexer.error

  (* Location of the last valid item *)
  type t = item Location.loc

  (** Create a new lexer *)
  val empty: filename:string -> t History.t

  (** Prepare for lexing.
      Returns the start position (end position of last valid token), and a
      lexing function that will append at most one token to the history at each
      call. *)
  val start: Raw_lexer.keywords -> t History.t -> Lexing.position * (Lexing.lexbuf -> t History.t)
end = struct
  type item =
    | Valid of Chunk_parser.token
    | Error of Raw_lexer.error

  (* Location of the last valid item *)
  type t = item Location.loc

  (** Create a new lexer *)
  let empty ~filename =
    let pos =
      { Lexing.
        pos_fname = filename;
        pos_lnum  = 1;
        pos_bol   = 0;
        pos_cnum  = 0;
      }
    in
    let loc =
      { Location.
        loc_start = pos;
        loc_end = pos;
        loc_ghost = true;
      }
    in
    History.initial (Location.mkloc (Valid Chunk_parser.ENTRYPOINT) loc)

  (** Prepare for lexing.
      Returns the start position (end position of last valid token), and a
      lexing function that will append at most one token to the history at each
      call. *)
  let start kw t =
    let rec aux = function
      | History.One l | History.More ({Location.txt = Valid _} as l,_) ->
        l.Location.loc.Location.loc_end
      | History.More (_,h) -> aux h
    in
    let pos = aux (History.head t) in
    let t = ref t in
    pos,
    (fun buf ->
       Raw_lexer.set_extensions kw;
       let value =
         try let token = Valid (Raw_lexer.token_with_comments buf) in
           Location.mkloc token (Location.curr buf)
         with Raw_lexer.Error (e,l) ->
           Location.mkloc (Error e) l
       in
       t := History.insert value !t; !t)
end

(* Project configuration *)
module Project : sig
  type t

  (** Create a new project *)
  val create: unit -> t

  (* Current buffer path *)
  val set_local_path : t -> string list -> unit

  (* Project-wide configuration *)
  val set_dot_merlin : t -> Dot_merlin.config option -> [`Ok | `Failures of (string * exn) list]

  (* Config override by user *)
  module User : sig
    val reset : t -> unit
    val path : t -> action:[`Add|`Rem] -> var:[`Build|`Source] -> ?cwd:string -> string -> unit
    val load_packages : t -> string list -> [`Ok | `Failures of (string * exn) list]
    val set_extension : t -> enabled:bool -> string -> unit
  end

  (* Path configuration *)
  val source_path : t -> Path_list.t
  val build_path  : t -> Path_list.t
  val cmt_path    : t -> Path_list.t

  (* List all top modules of current project *)
  val global_modules : t -> string list

  (* Force recomputation of top modules *)
  val flush_global_modules : t -> unit
end = struct

  (** Mimic other OCaml tools entry point *)
  module Flags = struct

    (* Parse arguments specified on commandline *)
    module Initial = Top_options.Make (struct
      let _projectfind path =
        let dot_merlins = Dot_merlin.find path in
        begin match Dot_merlin.project_name dot_merlins with
        | Some name -> print_endline name
        | None -> ()
        end;
        exit 0
    end)

    let () =
      (* Parse arguments on commandline *)
      Arg.parse Initial.list Top_options.unexpected_argument
        "Usage: ocamlmerlin [options]\noptions are:"

    (* Save flags, so as to restore them when changing project *)
    let initial_flags = Clflags.snapshot ()
    let reset_flags () = Clflags.restore initial_flags

    (* Parse flags specified at runtime (project-wide or entered by user) *)
    let err_log msg = Logger.error `dot_merlin msg

    module Incremental = Top_options.Make (struct
      let _projectfind _ = err_log "unsupported flag \"-project-find\" (ignored)" ;
    end)

    let enable_flags flags =
      begin try
        Arg.parse_argv ~current:(ref (-1)) (Array.of_list flags) Incremental.list
          Top_options.unexpected_argument "error..."
      with (* FIXME *)
      | Arg.Bad msg -> err_log msg
      | Arg.Help msg -> err_log msg
      end

    let default_path =
      let dirs =
        if !Clflags.use_threads then "+threads" :: !Clflags.include_dirs
        else if !Clflags.use_vmthreads then "+vmthreads" :: !Clflags.include_dirs
        else !Clflags.include_dirs in
      let exp_dirs = List.map (expand_directory Config.standard_library) dirs in
      let exp_dirs = List.rev_append exp_dirs (Clflags.std_include_dir ()) in
      ref exp_dirs
  end

  type config = {
    mutable cfg_extensions : Extension.set;
    mutable cfg_flags     : string list list;
    cfg_path_build  : string list ref;
    cfg_path_source : string list ref;
    cfg_path_cmi    : string list ref;
    cfg_path_cmt    : string list ref;
    cfg_path_pkg    : string list ref;
  }

  let empty_config () = {
    cfg_extensions = String.Set.empty;
    cfg_flags = [];
    cfg_path_build  = ref [];
    cfg_path_source = ref [];
    cfg_path_cmi    = ref [];
    cfg_path_cmt    = ref [];
    cfg_path_pkg    = ref [];
  }

  let reset_config cfg =
    cfg.cfg_path_build := [];
    cfg.cfg_path_source := [];
    cfg.cfg_path_cmi := [];
    cfg.cfg_path_cmt := [];
    cfg.cfg_path_pkg := []

  type t = {
    dot_config : config;
    user_config : config;

    mutable flags : Clflags.snapshot;

    local_path : string list ref;

    source_path : Path_list.t;
    build_path  : Path_list.t;
    cmt_path    : Path_list.t;

    mutable global_modules: string list option;
  }

  let flush_global_modules project =
    project.global_modules <- None

  let global_modules project =
    match project.global_modules with
    | Some lst -> lst
    | None ->
      let lst =
        Misc.modules_in_path ~ext:".cmi"
          (Misc.Path_list.to_strict_list project.build_path)
      in
      project.global_modules <- Some lst;
      lst

  let create () =
    let dot_config = empty_config () in
    let user_config = empty_config () in
    let local_path = ref [] in
    dot_config.cfg_extensions <- Extension.default;
    let prepare l = Path_list.(of_list (List.map ~f:of_string_list_ref l)) in
    { dot_config; user_config;
      flags = Flags.initial_flags;
      local_path;
      source_path = prepare [
          user_config.cfg_path_source;
          dot_config.cfg_path_source;
          local_path;
        ];
      build_path = prepare [
          user_config.cfg_path_cmi;
          user_config.cfg_path_build;
          dot_config.cfg_path_cmi;
          dot_config.cfg_path_build;
          user_config.cfg_path_pkg;
          dot_config.cfg_path_pkg;
          local_path;
          Flags.default_path;
        ];
      cmt_path = prepare [
          user_config.cfg_path_cmt;
          dot_config.cfg_path_cmt;
          user_config.cfg_path_build;
          dot_config.cfg_path_build;
          user_config.cfg_path_pkg;
          dot_config.cfg_path_pkg;
          local_path;
          Flags.default_path;
        ];
      global_modules = None;
    }

  let source_path p = p.source_path
  let build_path  p = p.build_path
  let cmt_path    p = p.cmt_path

  let set_local_path project path =
    project.local_path := path;
    flush_global_modules project

  let set_dot_merlin project dm =
    let module Dm = Dot_merlin in
    let dm = match dm with | Some dm -> dm | None -> Dm.empty_config in
    let cfg = project.dot_config in
    let result, path_pkg = Dot_merlin.path_of_packages dm.Dm.packages in
    cfg.cfg_path_pkg := List.filter_dup (path_pkg @ !(cfg.cfg_path_pkg));
    cfg.cfg_path_build := dm.Dm.build_path;
    cfg.cfg_path_source := dm.Dm.source_path;
    cfg.cfg_path_cmi := dm.Dm.cmi_path;
    cfg.cfg_path_cmt := dm.Dm.cmt_path;
    cfg.cfg_flags <- dm.Dm.flags;
    cfg.cfg_extensions <-
      String.Set.(union Extension.default (of_list dm.Dm.extensions));
    flush_global_modules project;
    result

  (* Config override by user *)
  module User = struct
    let reset project =
      let cfg = project.user_config in
      cfg.cfg_path_build := [];
      cfg.cfg_path_source := [];
      cfg.cfg_path_cmi := [];
      cfg.cfg_path_cmt := [];
      cfg.cfg_flags <- [];
      cfg.cfg_extensions <- String.Set.empty

    let path project ~action ~var ?cwd path =
      let cfg = project.user_config in
      let r = match var with
        | `Source -> cfg.cfg_path_source
        | `Build  -> cfg.cfg_path_build
      in
      let d = canonicalize_filename ?cwd
                (expand_directory Config.standard_library path)
      in
      r := List.filter ~f:((<>) d) !r;
      begin match action with
      | `Add -> r := d :: !r
      | `Rem -> ()
      end;
      flush_global_modules project

    let load_packages project pkgs =
      let result, path = Dot_merlin.path_of_packages pkgs in
      let rpath = project.user_config.cfg_path_pkg in
      rpath := List.filter_dup (path @ !rpath);
      result

    let set_extension project ~enabled path =
      let cfg = project.user_config in
      let f = String.Set.(if enabled then add else remove) in
      cfg.cfg_extensions <- f path cfg.cfg_extensions
  end

end
