sed -i 's/LONGINT/HUGEINT/g' *.Mod
sed -i 's/INTEGER/LONGINT/g' *.Mod
sed -i 's/SHORTINT/INTEGER/g' *.Mod
sed -i 's/BYTE/SHORTINT/g' *.Mod
sed -i 's/IN/VAR/g' *.Mod
sed -i 's/OUT/VAR/g' *.Mod
sed -i 's/POVARTER/POINTER/g' *.Mod
sed -i 's/BEGVAR/BEGIN/g' *.Mod
sed -i 's/LONGVART/LONGINT/g' *.Mod
sed -i 's/SHORTVART/SHORTINT/g' *.Mod
sed -i 's/VARTEGER/INTEGER/g' *.Mod
sed -i 's/HUGEVART/HUGEINT/g' *.Mod
sed -i 's/VARC/INC/g' *.Mod
sed -i 's/, NEW//g' *.Mod
