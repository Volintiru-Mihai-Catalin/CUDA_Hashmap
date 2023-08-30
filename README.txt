		Tema3 ASC

				Volintiru Mihai Cătălin 336 CA

Pentru această temă am implementat funcțiile puse la dispoziție și am pus
bazele clasei GpuHashTable, astfel că am considerat util să țin minte drept
atribute ale clasei următoarele: hash-table ul, dimensiunea lui, numărul de
elemente din el și numărul maxim de threaduri dintr-un bloc (pentru a-mi fi
mai ușor să calculez ulterior numărul de blocuri).

Pentru a insera elemente în hash table, prima dată verific dacă hash-table-ul
are capacitatea necesară pentru acest lucru. Dacă da, iau toate perechile
de tip cheie - valoare și le inserez cu ajutorul unui kernel. Dacă nu, creez
un nou hash-table și copiez toate perechile din cel vechi în cel nou folosind
un kernel. Pentru a face rost de elemente, mă folosesc tot de un kernel și
calculez poziția aproximativă unde ar trebui să se afle valoarea căutată.

Funcția de hashing am folosit funcția MurmurHash3, varianta curenta de
MurmurHash, care poate oferi valori pe 32 sau 128 de biți. În mare, motivul
pentru care am ales această funcție este pentru că oferă o distribuție de
valori destul de bună si pentru că e destul de eficientă când vine vorba de
evitarea coliziunilor.