import "io"

MANIFEST {
  blockLocation = 0,
  dirBlockLocation = 0,
  lastUsed = 1,

  dirName = 0,
  dirNameSize = 20,
  dirFileBlockLocation = 5,
  dirFileSize = 6,
  dirLastUsed = 7,
  dirSize = 8
}

let directory = VEC(128);
let superblock = VEC(128);
let nextBlock = 0;

let ins(destination, numToRead) be {
  let pos = 0, max = 4 * numToRead - 1, c = inch();
  while c = ' ' \/ c = '\n' do
    c := inch();
  while c > ' ' do {
    byte pos of destination := c;
    pos +:= 1;
    if pos > max then
      break;
    c := inch();
  }
  byte pos of destination := '\0';
  resultis destination;
}

let strcmp(stringA, stringB) be {
  let pos = 0;
  while true do {
    let charA = byte pos of stringA, charB = byte pos of stringB;
    if charA <> charB then
      resultis charA - charB;
    if charA = 0 then
      resultis 0;
    pos +:= 1
    }
}

let addto512(buff, s, n) be { 
  let i = 0;
  while true do {
    let c = byte i of s;
    if c = '\0' then
      resultis n;
    if n = 512 then
      resultis 512;
    byte n of buff := c;
    i +:= 1;
    n +:= 1 
  } 
}

let alloc() be {
  let block = nextBlock;
  nextBlock +:= 1;
  resultis block;
}

let mount() be {
  let dirBlock, success;
  success := devctl(dc$discread, 1, dirBlockLocation, superblock);
  if success <> 1 then
    out("Error Disc Reading While Mounting: %d\n", success);
  dirBlock := superblock ! dirBlockLocation;
  out("Previously used at %d\n", superblock ! lastUsed);
  out("Directory at block %d\n", dirBlock);
  success := devctl(dc$discread, 1, dirBlock, directory);
  if success <> 1 then
    out("Error Disc Reading While Mounting Directory: %d\n", success);
}
    
let dismount() be {
  let success;
  success := devctl(dc$discwrite, 1, superblock ! dirBlockLocation, directory);
  if success <> 1 then
    out("Error writing disc while unmounting: %d\n", success);
  superblock ! lastUsed := seconds();
  devctl(dc$discwrite, 1, blockLocation, superblock);
}

let format() be {
  let success;
  let now = seconds();
  let dirBlock = blockLocation + 1;
  $memory_zero(superblock, 128);
  superblock ! dirBlockLocation := dirBlock;
  superblock ! lastUsed := now;
  out("Successfully formatted at: %d\n", now);
  success := devctl(dc$discwrite, 1, blockLocation, superblock);
  if success <> 1 then
    out("Error writing while formatting superblock: %d\n", success);
  $memory_zero(directory, 128);
  directory ! 0 := 0;
  directory ! 1 := 0;
  success := devctl(dc$discwrite, 1, dirBlockLocation, directory);
  if success <> 1 then
    out("Error writing while formatting directory: %d\n", success);
}    

let make(name) be {
  let i = 0, slot = -1;
  /* There are 128/dirSize entries (here 16) */
  while i < 16 do {
    if directory ! (i * dirSize) = 0 then { slot := i; break }
    i +:= 1
  }
  if slot = -1 then {
    out("Directory full; cannot create new file\n");
    resultis -1
  }
  /* Copy file name (up to 20 bytes) into directory entry */
  let offset = slot * dirSize;
  let j = 0;
  while j < 20 do {
    let c = byte j of name;
    directory ! (offset + j) := c;
    if c = '\0' then break;
    j +:= 1
  }
  /* Allocate a block for file contents */
  let fileBlock = allocate_block();
  directory ! (offset + 5) := fileBlock;
  /* Accumulate file text in a 512-byte buffer */
  let buffer = vec(512);
  let total = 0;
  while true do {
    out("Enter text: ");
    let line = vec(100);
    ins(line, 100);
    if strcmp(line, "*") = 0 then break;
    total := addto512(buffer, line, total);
  }
  directory ! (offset + 6) := total;
  if devctl(dc$discwrite, 1, fileBlock, buffer) <> 1 then
    out("Error writing file to disc\n")
}

let import(tname, dname) be {
  let f = io$open(tname, "r");
  if f = -1 then {
    out("Error opening unix file: %s\n", tname);
    resultis -1
  }
  /* Find free directory slot */
  let i = 0, slot = -1;
  while i < 16 do {
    if directory ! (i * dirSize) = 0 then { slot := i; break }
    i +:= 1
  }
  if slot = -1 then {
    out("Directory full\n");
    resultis -1
  }
  let offset = slot * dirSize;
  let j = 0;
  while j < 20 do {
    let c = byte j of dname;
    directory ! (offset + j) := c;
    if c = '\0' then break;
    j +:= 1
  }
  let fileBlock = allocate_block();
  directory ! (offset + 5) := fileBlock;
  let buffer = vec(512);
  /* Read from Unix file (assumes the file fits in one block) */
  let n = io$read(f, buffer, 512);
  if n <= 0 then {
    out("Error reading from unix file\n");
    io$close(f);
    resultis -1
  }
  directory ! (offset + 6) := n;
  if devctl(dc$discwrite, 1, fileBlock, buffer) <> 1 then
    out("Error writing imported file to disc\n");
  io$close(f)
}

let export(dname, tname) be {
  let i = 0, found = -1;
  while i < 16 do {
    let offset = i * dirSize;
    if strcmp(directory + offset, dname) = 0 then { found := i; break }
    i +:= 1
  }
  if found = -1 then {
    out("Disc file not found\n");
    resultis -1;
  }
  let offset = found * dirSize;
  let fileBlock = directory ! (offset + 5);
  let size = directory ! (offset + 6);
  let buffer = vec(512);
  if devctl(dc$discread, 1, fileBlock, buffer) <> 1 then {
    out("Error reading disc file\n");
    resultis -1;
  }
  let f = io$open(tname, "w");
  if f = -1 then {
    out("Error opening unix file for writing\n");
    resultis -1;
  }
  io$write(f, buffer, size);
  io$close(f)
}

let help() be {
  out("List of available commands\n");
  out("help ~ Shows This page\n");
  out("format ~ reformats the disk or mounts if not already mounted\n");
  out("mount ~ sets up a formatted disc\n");
  out("exit ~ saves memory to disk and dismounts\n");
  out("make <name> ~ prompts user to type lines of text until a line of text containing only '*' is typed. It is then written to a new file with the given name.\n");
  out("show <name> ~ displays contents of name file.\n");
  out("import <tname> <dname> ~ read the unix files called tname and create a disc file with its contents called dname\n");
  out("export <dname> <tname> ~ write the contents of disc dname to a new unix file called tname.\n");
  out("status ~ display useful information about the system. Indicates current contents.\n");
}


let start() be {
  let word = vec(20);
  while true do {
    out("> ");
    ins(word, 20);
    test strcmp(word, "mount") = 0 then
      mount()
    else test strcmp(word, "format") = 0 then
      format()
    else test strcmp(word, "help") = 0 then
      help()
    else if strcmp(word, "exit") = 0 then {
      dismount();
      break
    }
    else if strcmp(word, "make") = 0 then {
      let filename = vec(20);
      ins(filename, 20);
      make(filename)
    }
    else if strcmp(word, "show") = 0 then {
      let filename = vec(20);
      ins(filename, 20);
      show(filename)
    }
    else if strcmp(word, "import") = 0 then {
      let tname = vec(20), dname = vec(20);
      ins(tname, 20);
      ins(dname, 20);
      import(tname, dname)
    }
    else if strcmp(word, "export") = 0 then {
      let dname = vec(20), tname = vec(20);
      ins(dname, 20);
      ins(tname, 20);
      export(dname, tname)
    }
  }
}

    

  
