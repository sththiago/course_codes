#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

echo -e "Grade for $BASE$EXT: $(cat grade)"

cleanup || true

exit 0

__TESTBENCH_MARKER__
� 菖[ �=kW�H��ٿ�qc;��]�f�g�3r����$WG�mЍ-y%�~̞��~�_�?v��!uK����gΠsl��������rD��zË���Ձ���&��>����]wc���f�9��]�Y��l~;��kFN@�w΄~t�|����+����$�&Z���76�>��^����gD�W��]e��<-�����w�sw$�_r�?ZZ;s��3'������/wk{��ӝ��zm����iy����/?���~������YC�!m�ԗ��:��w�����7�Ljc? .q=���?�2�i��ȯN(��e�3|���_��c@�gu>�F�Gk�4r ktA=@D�>������.�D���Eh8���|2uܐ̧d�χ��'O���H+�$8Cr)ф0�	�D�$���\%�����f�\h��+G��M�34݈tqLnm�Rc7:5)���.�S���.t�d��od���gO���\����|��7��^���Zƿ��pƽ%�Ϡ�1\��O͵�n��9azD@�f�toB�=�?��>͘�љ3�P�I���WA�:t��Y�p*m��ؗ���Idcgd�3?�\߃�ޚ���A��t�諍�ސ5;�Q{�{�"Ұ� �i����}�_n�`Eڃ06���ѣG�ݭ:a���i�I��G[���:#��]p$�W`c�7��<�،�."ǝ ��r�!aW��%;ɒ�����7���@XO*����N%&|̚�%����$��xCY�&�V�HqJj���s���o^�;�3�/�X&�g�H��5^gdiP�Y��xxC� )�;�CV�����S_v�V]����Y��log��#���jh����Q�*WV�H��:�cX濸� �r��{&�e�^4&�ꏟ����[��t]��,�/� Sӣ�����e"�#�d�Oa�S@����T�|�k3�cXn�� U+d��>\{���Y[;�ު�m�P�j���q%��ҙ�#'�v|��ŝ�N��ӧy����<M��������;�FtLl��;�{;�G����������/�/�]{�]����G�7���b�-�FNp��b[��A7ށlW�fvtf��5���^8A�Īg�j��;��G�4�?5��Q�����w6�`V�1��g��� 3�MY�ߘ�����!�F�^��@�|�R���*��ٕ/lT��7�B��K���m��)��H�$C���f���k��O|����Qb��=}���������4�����v�~,$f�{��{���4u��m��K�xԍ ���&��>�E�f]��}_X0�9�3{�D=��c��X����f��aj׫]��6[�}����Ht�Ϩ�;#@�9S�Ҩ���w8�����3h١UCE�D̂����D�n[-��O��O��"F,1�q��Z={3�Ξ01��M���>��fm���ݟ�lَ��OƤ��M�R<��F���&me��^̲�� �F�FS���V�n�!�	1ő��o�`�����$���	ˮ�q@)�R�z�IvW��Bq���MTA?1\/�M�5�~]� ?����������E:X���� �ܒ�tm
��Q������d�;���C��}<��!m��nU`��냃�����I~��1���O!%a"��[-l (��k��g
��۠��H���!NW��V�����R�|���^��q�ucM�)MV���d�J�-T%�!�	���|�˟w��h� ���.&l����ؚ�D�I�R 0��0�a�'���?W�)-Y>	-�Fx͖}TQ,le��!L�I@��'�f�h�W7���	�k�i�jۺ��F��n�)NCp�8wi����L�A��������d1�.��?ZqJ�qs��k3�9	��2�JF!P����u!����f��|�_�kޣ�x>Ǿ�E���Ƿ�\��
/��_-��qr�����Bbd_(�!��}N#�i�2�{ytxtzt���"@��(��?
Yl�rЭ���2���y����%�@�tY$߀O�KDB�����m�M@H>s'���'�r�G�x��MS����~�B�J:��N��4Ƌ���'*p[�ͱ��v����ng��V����x�݉�]��?ɲ���ٳ�t��[���=\����A�-�j �98��#�#�1����]7=<=9`A�,���~d��Eީin9��G�5�sj_Q�|�M�!d=jKH���>�~ q���1w��Љ�,9@��`��#'��t�Vc��d��vm̙[l]T�=���U	fQ���R`�N7C�*��Dar�d԰z���P0���d�j���7Bq]�Q
)�ɠ+ӡK$GUW�XI,^�SP\��2�`�;+��h�F�,�N̓NVשR�Q�A����5/T_��zPd~�|#x	����(�4F��K��BE*�F:.pF�7�elYp:�� DΨx:T�<7��ng�j��;A2�;-��m�d��4&)3�s��Tw{��u��o]`r�d��n�(��:�763����C�wW�e�N�ߎw^�����<���k�D�%�SSw1aHݚ{�����L��O�]V��)� ?�����t��$�o�M�X��>��/7��QgxA��r#b��������]ˀ����
~��Xt4{�'}�~}2������b�::�c��'G��w��N�/��d���0��v[A�E���ҿ�����]O���/�)�{u���`g/7�S�c�7&Kj�H���5��!��7h���a��~4�̏/�?�%ũ^�*h�0C��*N������I�~�٤��t��.`��X�d�5�F3Y&�E��%��gvd5�	�9�ys�E��a�1j�a A?F����\@�� "������d�[��b��+��;��+�1͎��O�(1y������t ���l��CfA:�,3�R	e 	�N^GB,�P�4������y��FC��=B@dX�O51S��* B3F?.W�Vl1��i(����[���*v�
��t�����*��ϟ={�����/���*�X��Ղ���d���f��lp�y�aZ���:��J�S,�Bar+\�?v����΃н��]tL�=��^�o��G<�7��;���]8ĭj���8ckڌ<R
�0��A��P}VG'j`��1��x�5��oP�9�� ��,G�!��	����\�!9��~��\H��D��9k���i��Yү�|}:xc�����Xw�Md�F��&�jP{�DQ���o�8�|�<�1vP����o�^f��C4W��"�e2 �ioB W'l���-0/���Z���>�fR��)ge%�xID#pA+�,�:�|�`�< �~�v�)�[%�x�)�q��j�z��H�����7��/�L���!���:6-�9��Z%AB�(�����K��7+M�:I,aq'��I�$}�^ئ��B�/X&C����@e���a�D������a�Eg��w�_VW�k{[8�|���u�f�����������?{ݔb����Ԅ�Q�/�ރ�Բ~J=T�K\y�'�*�� ����O���_�5��K�Q�^Hiq{�l|dY�'�*�s��A�����d秃����9Q|%|Z�R<}��9�b\e��J �9���d������1$2B.6��;�����e���wIY�-�"%�	&�n:%�YT櫮O9;t��Q���i�b���	�G��{�+��4�fD:$�ʹ�{�.������m���x63Ͷ,�3�$X]��o!�^�	���}���A.@,��<D, Z��(�`���|&2�wt�,WO�`كV^�����E�pG)D|��t�ǃ���'�X��V��:gࡠhEP#��������m;fI����ȣa����t� T�̕b�p�:[���<��qKI��ۨKxb(�΍����|rE�G�1~�A]Pn~H�L��t���l��bG�qZ�-Kxa���uN�>n^�`X�>��ylt�\,L{9q�
g&����BQq~K���#Z�k"�H��!2Y�LDXj�o��`��n�0t��g��e7��	���yJ}���D� ���y�}����vDZ�"p�9�?��2G9�P�a�����d�I���������$�E�c)ױ:���yq�T^-O<|��F�)y�M��|����	F��.{KV=:aV!�bw�B��)/ST-5�KY�S����>֢�m1��ȋ��`�U�P�>bA�Lf {!�x�0+�+l\��X@����<��4�꣖1t�?��AZ|ye����g;��f6���R>��B��{	�ŋjJ��<�Q2�nI��eblD[�$sa�����t|'��M����)\��*˝���<���P��ΰ"�dŇ��k�~a��D���eT���U�.^@1R'�S�����f��Ÿ99���Ph�|ܰ/X<O�iN�n`��=���g�-�o��xU!��EG�Ȇ���1�|Rc��ZT㴡Zq��J�:+��y�s���XW�B!뵩rB�a��Gy���&�� �!��,��\�s%�a�
�`j6���i���~������i�õ�Ҫ���&��w���,�ʪX��x��8��TL���}����T�b���0!�LJ<i&R<�^�J*h�t-�b�$_J+cNģGl?978f�9w�:-�*a�Vts��ֲ�2c.c]�ک[�v8�Ni� ���U�Q��GL@�
���0�o������.������l,��;f�4�u�P�Ԋ�#:�͍T���+���w���$9�R�%�U���.M-�-ȣ*m��@�ћH�:�O��(k	�%��U������Ij��؛���w��"|w�+w�7���cl��y3M:!�c����8��M��V!�D�ˢ��c%9*�O�L�0\��+r+��r�g�S��\�(��S+�<�E�]9�%A|B���d_�1��Y��F1Wq�k_n�5ߨ�׭4��j�d��++$�M��8��r2nX���(��}<;��(ۨ��H�y��cے�mf��lٟ�3³�n@<�c/����K���t��%b@ {�To�(��)�b�S�D	��e:�EE�����W�^*��LMQ�@ɵ�L��uEufr�t���H�o^ v=Ozcȣ�62��{�����C�;|V������F�o����"������DYTbzI
|�$G��1�������x�ʑM��P��F���)4#5Zi��7�>�>BpI蘼! ,qE��H�X�%�mv��1�{:�|�{%5H��������ORQ��T�%A���!bT3^L�s�?����9Ll�s&q�	�L�]'$���oY 1[��۸%��Jr���ŨE�:�j���;������N��_|B�[��Ŝ����(�fF�F���챊�����:?�zVJ����]'�\�^Q�d�%�����?������|^�X&R���.�d��u���t�X��N$+����P�D�ȬD��>�P]AdK+G�'m�V�#�z�R��a�6��1��×-o;|ēzU��}5�ʞ���\6��ޗ�59Jg��`C�&�E��T���9���Hp1�{�^�w&Fd!�O��/{G�Oc>Y[�|0�? XQ�	�**@���2N�Z����6C�7����;��w!R��j5��.P��m�^ξ�jʂ��UH��4���D[�d2�YS�N�2$l�r2W���]�.׋d5;��>��K�!�����!;>����"u��Bё">��6��r�
J���K��ϰ��:�[U���ߕa|�Cr��N�({�S'��'�I���?��e|��8��Ϋ�7@i��Pޙ~^:A?���t�aj�d�r�L4���u:�Բ퀃b%���J�b)��xfA�1��:&k��֤ߌ�ٔ�.|�M������?
<̬̈_�!�5#����н�wKŵ���@2!Ht�U����;nў���WZq/a(�Շ�$b������	��~�����im�*���Э��1�2K���qV�2��K�~x�ҟ�*���������>}������U��&ï�.�B&����*�~�LD�h�5�3��H7��{~o����0�eό���%�rV� Jb�$����:E�S�е���C��-x�>NbxUў%}�O���`)��3��Ù%�W���l�T��ٌL�w�Ɵ[S���'~�����]�7N {���i�֙g����}��Sg��ܵ2�V�g���oO	kq��{�3B�������7R�z��:&�FZ∱8�PT�{_�Δ�Z8
��O�KӲ�[�r��_����f�Ao@(�R*�c!3.+���N�H�Y/,��:��w��E<o5E�	��Z
�[F#���'ِF����wm�qW�Y�#y��"W+[)��:qd�Q!K�%;(�&�����r�
ɏ�SP}2����c���׵W	8�eI��3g�mnU���)�P�2zV����=Y���1l#�-߅�G�mf��^�r!S4瞷8�Ɇ5�~|Ln�~�����x\,y[����F�����O�V�S�����}*��F�	�@�-DBe����Lo׬GS1S�[��a���z�:�b>ح-\�H�%7�j�r������'R���j�*!e�`�$��	x�L���(��j�H���-JFr� �������^�>j���T����O`����#���,l/�0煛:jS�l�d9Q[嫇��P쟭�E�	"��x���H���Ssζ6�,�f�y,i����M��L�C�JPu�!����~+3{Ķal��R�o��<I�������&K��f�r�+�鬆$�T#�$	���uo�FC�'4r�����W����n��2��G+WU�#�:+,�4����	�Q��[�׶
�^����%�5�ܦH�ɨ߮�V�m�ͅ�QU` ��]���#6r�Q��1�;m\K�W�KEk�-��VT_�ۼ�֌����a��r��V��o��D��u[�V���'y[�����x�����7����{�����>A��><���9���9��	�2���a��z�z_���� II�1w!H�*����Ѕկ�g'/�&��u��Gl��0�f�]u�ۋ���+�O��Y��-���\=�!�M��P�S_r	m��~�-7f�Ѭ����s�9���>�P� �/�8X�G�t۱?�_Yt��\�l� 4إc��`�����f2WUF5�7v���j˺�5�@����(w��ҙ�(K����!���f�}a�<���s`5ylu�U_ؖ��v��O��X�"���}jY��n"�"+��tW�-�>7�v��R��b�޿�K?*i���/wZ��A����;n�X6Qdnx^}/�2�v���|�q�~�[�1S���%�C���Na��'�;]�,�A-�3�*R.յ��[!���.r�{ ��Z��c��ۦk�=�jL>�!b�t���r�a�2k2��i�<+��&�B��:�ͫ,�l�m֕p	MU�>���S��p�ů�SIq�h;���<�� � �]*ܔ{|}�Bɣ���s��������X��%н���oT|��������/V՗mr2�2݈g\zz1j���yf3�Ql�[^��e4-hv�+w��x�^���>HߋJ�ia��7!A�U���1�c�§���O���'�A�P��".�k�,��`�Q�t�V��!�Vw۪� �A�������R�k���X��w��4j������O���>~v:1QxfO�}������f�k1ភ)��zV���Y����,`֓��G��r*�%ye^�rM�d.�� �������M���9.�1$��\�$PI3å�Ep���MF1=�52�o�4��B-�E�#>UM�F� ���"�W���B���o̐�Bp�!�
�}���@��)6�x'�~�-�A�-�N�T_*�1��:h.8E���Tρ��0 �e�����q �m�� 8�H�1�I�!��<t�gs�;�\��Ӟ�ҏ��!��$��g�z�ϟ?�?'����g����9g��2��0%��ծ	9K��td���I��O=���?�"�'<n���g��ܕy��FQB�,�T�d\S���J,���yj�P�1O��VA�m��=:�%��G^S5V�&?;~�x��]껀���	�������H�S��˔�Ժ��N�s\�el��Wpe�w���f��y@=�g�M�f_J�ɣR�`��b,�'�D#��4Ċ���bX:x��5�i� O�9����ocj�ڊjCEB�ac�3NSO4���&� z�xK�*&j�J^���K��3\��̎Y��{r�b���=*"=�\*ګO<�ÇQ�g�HS]������q��D�O�J��b$ލ�~7�P�q̧\�D�%mG���L��Bߍ�+��Hj�LD<D���q�*i��Lq��2Z�"F��6�0x22ơA��L�[m�`V���s-��Hp$DqD`�B�v��c��t��5��w0=_��Զ%�~&������_5�D�<q��Ǚ"3Ϟ���_�������8a6�É;�4�4/�mD�] j�sf_T�O�[-�I�̽D~���0��K~u�UӸ��X� ��9k�`��-��e�������7����4e���5{��+�D���u�$��T��$*&�@�8�k�^r$h8�;Q�ͨÏ�T+<N�K��DN����&��%��Qc�$ɘYk_�����������^E.ԗa` �����K��K-�-��Ê%�'�{� �<�l���X"���*�: �{��O�a\?��[*w�i���p�ٹ*�#-���ZKpM�˕!O�!�g�i��iJ��$�tX�:"�Ӡ-����w��4��jJ��Pu͠}@�H����46�+���rP"o�v��E>���K��y�E�iZ�^x�� ������㗧�r2�F�R���߼��<������L}b:x7��]� dI��_*��"�����)Q�jW
������Ы��9��#fKJ�s�]�R��ԥ.u�K]�R��ԥ.u�K]���A��Jz �  