PROGRAM = project1

all: compile assemble link

compile:
	bcpl $(PROGRAM)

assemble:
	assemble $(PROGRAM)

link:
	linker $(PROGRAM)

run: all
	run $(PROGRAM)

prep:
	prep $(PROGRAM)

clean:
	rm -f $(PROGRAM).ass $(PROGRAM).obj $(PROGRAM).exe
  
