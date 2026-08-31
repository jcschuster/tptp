%----Our own Broken.p: independent, individually recoverable errors.
%----Every statement here is malformed in exactly one way, and the good
%----statements on either side of each must still come through intact.
fof(fine, axiom, p).
wibble(unknown_language, axiom, q).
$fof(not_a_word, axiom, q).
.
fof(illegal_character, axiom, p ; q).
fof(stray_closer, axiom, p)).
fof(fine_again, axiom, r).
