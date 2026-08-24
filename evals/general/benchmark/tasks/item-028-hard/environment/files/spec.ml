(*
 * spec.ml -- the "bootstrap spec" stage of the project.
 *
 * Runs under the OCaml runtime and emits the on-disk stream "rcode.dat".
 *
 *   rcode.dat layout: [count:u8][value:u8]  per run
 *
 * This is the layout *contract* between the OCaml bootstrap and the C runtime;
 * it must not be edited.
 *)
let () =
  let os = open_out "rcode.dat" in
  (output_char os (Char.chr 3);
   output_char os (Char.chr 0x41);

   output_char os (Char.chr 160);
   output_char os (Char.chr 0x42);

   output_char os (Char.chr 2);
   output_char os (Char.chr 0x43);

   output_char os (Char.chr 130);
   output_char os (Char.chr 0x44);

   output_char os (Char.chr 1);
   output_char os (Char.chr 0x45);

   output_char os (Char.chr 255);
   output_char os (Char.chr 0x21);

   output_char os (Char.chr 1);
   output_char os (Char.chr 0x46);

   close_out os)
;;