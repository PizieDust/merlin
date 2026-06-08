Locating each segment of a dotted `open A.B.C` path must jump to the
corresponding module, both in implementations and interfaces.

  $ cat >test.ml <<'EOF'
  > module A = struct
  >   module B = struct
  >     module C = struct
  >       let x = ()
  >     end
  >   end
  > end
  > 
  > open A.B.C
  > EOF

Cursor on `A` jumps to module `A` (prefix segment, textual fallback):

  $ $MERLIN single locate -look-for ml -position 9:6 \
  > -filename test.ml <test.ml
  {
    "class": "return",
    "value": {
      "file": "$TESTCASE_ROOT/test.ml",
      "pos": {
        "line": 1,
        "col": 7
      }
    },
    "notifications": []
  }

Cursor on `B` jumps to module `B` (prefix segment, textual fallback):

  $ $MERLIN single locate -look-for ml -position 9:8 \
  > -filename test.ml <test.ml
  {
    "class": "return",
    "value": {
      "file": "$TESTCASE_ROOT/test.ml",
      "pos": {
        "line": 2,
        "col": 9
      }
    },
    "notifications": []
  }

Cursor on `C` jumps to module `C` (full open path, resolved by the typer):

  $ $MERLIN single locate -look-for ml -position 9:10 \
  > -filename test.ml <test.ml
  {
    "class": "return",
    "value": {
      "file": "$TESTCASE_ROOT/test.ml",
      "pos": {
        "line": 3,
        "col": 11
      }
    },
    "notifications": []
  }

The same should hold in an interface:

  $ cat >test.mli <<'EOF'
  > module A : sig
  >   module B : sig
  >     module C : sig
  >       val x : unit
  >     end
  >   end
  > end
  > 
  > open A.B.C
  > EOF

Cursor on `A`:

  $ $MERLIN single locate -look-for mli -position 9:6 \
  > -filename test.mli <test.mli
  {
    "class": "return",
    "value": {
      "file": "$TESTCASE_ROOT/test.mli",
      "pos": {
        "line": 1,
        "col": 7
      }
    },
    "notifications": []
  }

Cursor on `B`:

  $ $MERLIN single locate -look-for mli -position 9:8 \
  > -filename test.mli <test.mli
  {
    "class": "return",
    "value": {
      "file": "$TESTCASE_ROOT/test.mli",
      "pos": {
        "line": 2,
        "col": 9
      }
    },
    "notifications": []
  }

Cursor on `C`:

  $ $MERLIN single locate -look-for mli -position 9:10 \
  > -filename test.mli <test.mli
  {
    "class": "return",
    "value": {
      "file": "$TESTCASE_ROOT/test.mli",
      "pos": {
        "line": 3,
        "col": 11
      }
    },
    "notifications": []
  }
