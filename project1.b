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
      break;
    }
  }
}

    

  
