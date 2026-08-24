Core War is a programming game in which warriors — self-modifying assembly programs in the Redcode dialect — compete in a cyclic memory space called the *core*. Warriors gain advantage by spreading processes, moving, and destroying opponent processes.

A widely used strategy is to **multiply processes**: a warrior repeatedly spawns duplicate processes that run in parallel, so an opponent must kill several streams at once. In the Redcode dialect, exactly one instruction performs a process split: it starts a new (forked) execution stream at a given address while the original process proceeds to the next instruction.

Question: write the canonical **three-letter mnemonic** of that single process-forking instruction into `/app/answer.txt`, upper case.