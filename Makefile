CC=ocamlopt -annot -g
PARSERLIB=parser.cmxa
LANGUAGELIB=systemj.cmxa
LOGICLIB=logic.cmxa
ERRORLIB=error.cmxa
CODEGENLIB=codegen.cmxa
UTILLIB=util.cmxa

all: compile

compile: .ocaml-prerequisite
	$(MAKE) -e -C error/ all
	$(MAKE) -e -C language/ all
	$(MAKE) -e -C induction/ all
	$(MAKE) -e -C parser/ all
	$(MAKE) -e -C util/ all
	$(MAKE) -e -C backend/ all
	ocamlfind $(CC) -pp "camlp4o pa_macro.cmo -UDEBUG -USDEBUG" -o	\
	systemjc -syntax batteries.syntax -linkpkg -package batteries	\
	-package sexplib -package parmap -thread	\
	-I ocaml-pretty/_build -I ./language -I ./error -I ./parser -I ./induction -I ./util -I	\
	./backend $(ERRORLIB) $(LANGUAGELIB) $(LOGICLIB) $(PARSERLIB)	pretty.cmxa \
	$(UTILLIB) $(CODEGENLIB) systemjc.ml
	ctags -R .

clean:
	$(MAKE) -e -C language/ clean
	$(MAKE) -e -C error/ clean
	$(MAKE) -e -C parser/ clean
	$(MAKE) -e -C induction/ clean
	$(MAKE) -e -C util/ clean
	$(MAKE) -e -C backend/ clean
	$(MAKE) -e -C testsuite/ clean
	rm -rf *.ll *.lle *.bc *.s *.dot *.grf *.part* gmon.out TAGS *.mli *.cm* *.o systemjc \
	*.xml *.annot *_spi* *_ver* *.pml.trail 
	rm -rf .ocaml-prerequisite ocaml-pretty

.ocaml-prerequisite: ocaml-pretty
	opam install -y ocamlfind type_conv sexplib batteries	pa_sexp_conv parmap
	touch .ocaml-prerequisite

ocaml-pretty:
	git clone https://github.com/t0yv0/ocaml-pretty.git
	cd ocaml-pretty ; ocamlbuild pretty.cma pretty.cmxa



