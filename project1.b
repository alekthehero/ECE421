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

/* Global variables */
let directory = VEC(128);
let superblock = VEC(128);
let fsMounted = 0;         /* 0 = not ready, 1 = ready (mounted or formatted) */
let nextBlock = 0;         /* Next free block number */
let maxDirEntries = 16;    /* 128/dirSize */
let maxBlock = 1024;       /* Maximum block number allowed */

/* 
   Utility: Read a word (token) from input.
   Declarations come before executable code.
*/
let ins(destination, numToRead) be {
  let pos, max, c;
  pos := 0;
  max := 4 * numToRead - 1;
  c := inch();
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
  resultis destination
}

/*
   Utility: String compare.
*/
let strcmp(stringA, stringB) be {
  let pos, charA, charB;
  pos := 0;
  while true do {
    charA := byte pos of stringA;
    charB := byte pos of stringB;
    if charA <> charB then
      resultis charA - charB;
    if charA = 0 then
      resultis 0;
    pos +:= 1
  }
}

/*
   Utility: Append a null-terminated string s into buff starting at position n.
   Returns the new position. Warns if block full.
*/
let addto512(buff, s, n) be {
  let i, c;
  i := 0;
  while true do {
    c := byte i of s;
    if c = '\0' then resultis n;
    if n = 512 then resultis n;  /* block full */
    byte n of buff := c;
    i +:= 1;
    n +:= 1
  }
}

/*
   Allocate the next free block. Returns -1 if none available.
*/
let allocate_block() be {
  let block;
  if nextBlock >= maxBlock then {
    out("Error: No free blocks left\n");
    resultis -1
  }
  block := nextBlock;
  nextBlock +:= 1;
  resultis block
}

/*
   findEntry: Given a file name, return the directory entry index (0..maxDirEntries-1)
   if found; return -1 if not found.
*/
let findEntry(name) be {
  let i, offset;
  i := 0;
  while i < maxDirEntries do {
    offset := i * dirSize;
    /* If unused, the first byte will be 0 */
    if directory ! offset = 0 then {
      /* skip empty entry */
    }
    if strcmp(directory + offset, name) = 0 then
      resultis i;
    i +:= 1
  }
  resultis -1
}

/*
   createEntry: Creates a directory entry for a new file.
   Stores the file name (up to 20 bytes), file block, file size, and current time.
   Returns the directory index on success, or -1 on error.
*/
let createEntry(name, fileBlock, fileSize) be {
  let i, slot, offset, j, c;
  slot := -1;
  i := 0;
  while i < maxDirEntries do {
    if directory ! (i * dirSize) = 0 then {
      slot := i;
      break
    }
    i +:= 1
  }
  if slot = -1 then {
    out("Error: Directory full\n");
    resultis -1
  }
  offset := slot * dirSize;
  j := 0;
  while j < dirNameSize do {
    c := byte j of name;
    directory ! (offset + j) := c;
    if c = '\0' then break;
    j +:= 1
  }
  directory ! (offset + 5) := fileBlock;
  directory ! (offset + 6) := fileSize;
  directory ! (offset + 7) := seconds();  /* modification time */
  resultis slot
}

/*
   mount: Read the superblock and directory from disk.
   Also sets nextBlock and marks fsMounted as ready.
*/
let mount() be {
  let dirBlock, success;
  if fsMounted = 1 then {
    out("Disk already mounted\n");
    resultis 0
  }
  success := devctl(dc$discread, 1, dirBlockLocation, superblock);
  if success <> 1 then {
    out("Error: Disk reading superblock failed: %d\n", success);
    resultis -1
  }
  dirBlock := superblock ! dirBlockLocation;
  success := devctl(dc$discread, 1, dirBlock, directory);
  if success <> 1 then {
    out("Error: Disk reading directory failed: %d\n", success);
    resultis -1
  }
  nextBlock := dirBlock + 1;
  fsMounted := 1;
  out("Mounted disk. Directory block: %d\n", dirBlock);
  resultis 0
}

/*
   format: Initialize (or reformat) the disk.
   Clears superblock and directory, sets the directory block,
   updates the free block pointer, and marks the disk ready.
*/
let format() be {
  let now, dirBlock, success;
  now := seconds();
  dirBlock := blockLocation + 1;
  $memory_zero(superblock, 128);
  superblock ! dirBlockLocation := dirBlock;
  superblock ! lastUsed := now;
  success := devctl(dc$discwrite, 1, blockLocation, superblock);
  if success <> 1 then {
    out("Error: Writing superblock failed: %d\n", success);
    resultis -1
  }
  $memory_zero(directory, 128);
  directory ! 0 := 0;
  directory ! 1 := 0;
  success := devctl(dc$discwrite, 1, dirBlock, directory);
  if success <> 1 then {
    out("Error: Writing directory failed: %d\n", success);
    resultis -1
  }
  fsMounted := 1;
  nextBlock := dirBlock + 1;
  out("Disk formatted at time %d\n", now);
  resultis 0
}

/*
   dismount: Write the directory and superblock back to disk,
   then mark the disk as no longer mounted.
*/
let dismount() be {
  let success, dirBlock;
  if fsMounted = 0 then {
    out("Error: Disk not mounted\n");
    resultis -1
  }
  dirBlock := superblock ! dirBlockLocation;
  success := devctl(dc$discwrite, 1, dirBlock, directory);
  if success <> 1 then {
    out("Error: Writing directory failed: %d\n", success);
    resultis -1
  }
  superblock ! lastUsed := seconds();
  success := devctl(dc$discwrite, 1, blockLocation, superblock);
  if success <> 1 then {
    out("Error: Writing superblock failed: %d\n", success);
    resultis -1
  }
  fsMounted := 0;
  out("Disk dismounted.\n");
  resultis 0
}

/*
   make: Create a new disk file.
   If a file with the given name already exists, report an error.
   Otherwise, prompt the user to enter text lines (each ending with a newline)
   until a line containing only "*" is entered. The accumulated text is written
   to a newly allocated disk block.
*/
let make(name) be {
  let slot, fileBlock, buffer, total, line, result;
  slot := findEntry(name);
  if slot <> -1 then {
    out("Error: File already exists\n");
    resultis -1
  }
  fileBlock := allocate_block();
  if fileBlock = -1 then resultis -1;
  buffer = VEC(512);
  total := 0;
  while true do {
    out("Enter text: ");
    line = VEC(100);
    ins(line, 100);
    if strcmp(line, "*") = 0 then break;
    total := addto512(buffer, line, total);
    if total = 512 then {
      out("Warning: Data truncated; block full\n");
      break
    }
    /* Append a newline if room remains */
    if total < 512 then {
      byte total of buffer := '\n';
      total +:= 1
    }
  }
  result := createEntry(name, fileBlock, total);
  if result = -1 then {
    out("Error: Failed to create directory entry\n");
    resultis -1
  }
  test devctl(dc$discwrite, 1, fileBlock, buffer) <> 1 then {
    out("Error: Writing file to disk failed\n")
  } or {
    out("File %s created with %d bytes\n", name, total)
  }
  resultis 0
}

/*
   show: Display the contents of a disk file given its name.
   Searches the directory for the file, reads its disk block, and prints its content.
*/
let show(name) be {
  let index, offset, fileBlock, size, buffer, k;
  index := findEntry(name);
  if index = -1 then {
    out("Error: File not found\n");
    resultis -1
  }
  offset := index * dirSize;
  fileBlock := directory ! (offset + 5);
  size := directory ! (offset + 6);
  buffer = vec(512);
  if devctl(dc$discread, 1, fileBlock, buffer) <> 1 then {
    out("Error: Reading file from disk failed\n");
    resultis -1
  }
  k := 0;
  while k < size do {
    out("%c", byte k of buffer);
    k +:= 1
  }
  out("\n");
  resultis 0
}

/*
   importFile: Read a Unix file (emulated as a magnetic tape) named tname
   and create a disk file with name dname. (Error if tname doesn't exist or if dname already exists.)
   (Assumes file fits in one block.)
*/
let importFile(tname, dname) be {
  let slot, fileBlock, buffer, n, result, f;
  slot := findEntry(dname);
  if slot <> -1 then {
    out("Error: Disk file %s already exists\n", dname);
    resultis -1
  }
  f := io$open(tname, "r");
  if f = -1 then {
    out("Error: Unix file %s not found\n", tname);
    resultis -1
  }
  buffer = vec(512);
  n := io$read(f, buffer, 512);
  io$close(f);
  if n <= 0 then {
    out("Error: Reading unix file %s failed\n", tname);
    resultis -1
  }
  fileBlock := allocate_block();
  if fileBlock = -1 then resultis -1;
  if devctl(dc$discwrite, 1, fileBlock, buffer) <> 1 then {
    out("Error: Writing file to disk failed\n");
    resultis -1
  }
  result := createEntry(dname, fileBlock, n);
  if result = -1 then {
    out("Error: Failed to create directory entry\n");
    resultis -1
  }
  out("Imported %s as %s with %d bytes\n", tname, dname, n);
  resultis 0
}

/*
   exportFile: Write the contents of a disk file named dname to a Unix file named tname.
   (Error if the disk file dname does not exist.)
*/
let exportFile(dname, tname) be {
  let index, offset, fileBlock, size, buffer, f;
  index := findEntry(dname);
  if index = -1 then {
    out("Error: Disk file %s not found\n", dname);
    resultis -1
  }
  offset := index * dirSize;
  fileBlock := directory ! (offset + 5);
  size := directory ! (offset + 6);
  buffer = vec(512);
  if devctl(dc$discread, 1, fileBlock, buffer) <> 1 then {
    out("Error: Reading disk file failed\n");
    resultis -1
  }
  f := io$open(tname, "w");
  if f = -1 then {
    out("Error: Could not create unix file %s\n", tname);
    resultis -1
  }
  io$write(f, buffer, size);
  io$close(f);
  out("Exported %s to unix file %s\n", dname, tname);
  resultis 0
}

/*
   status: Display the current state of the file system.
   Prints superblock info and a directory listing.
*/
let status() be {
  let i, offset, name, fileBlock, size, modTime;
  out("Superblock:\n");
  out("  Directory block: %d\n", superblock ! dirBlockLocation);
  out("  Format time: %d\n", superblock ! lastUsed);
  out("Next free block: %d\n", nextBlock);
  out("Directory Listing:\n");
  i := 0;
  while i < maxDirEntries do {
    offset := i * dirSize;
    if directory ! offset <> 0 then {
      name := directory + offset;
      fileBlock := directory ! (offset + 5);
      size := directory ! (offset + 6);
      modTime := directory ! (offset + 7);
      out("  File: %s, Block: %d, Size: %d, Modified: %d\n",
          name, fileBlock, size, modTime)
    }
    i +:= 1
  }
  resultis 0
}

/*
   help: List available commands.
*/
let help() be {
  out("Commands:\n");
  out("  help              - show this help message\n");
  out("  format            - reformat the disk\n");
  out("  mount             - mount an existing disk\n");
  out("  dismount          - dismount and save disk data\n");
  out("  exit              - exit the program (confirmation if still mounted)\n");
  out("  make <name>       - create a file by typing text (end with a line '*')\n");
  out("  show <name>       - display the contents of the file\n");
  out("  import <tname> <dname> - import a unix file as a disk file\n");
  out("  export <dname> <tname> - export a disk file to a unix file\n");
  out("  status            - show system status\n");
  resultis 0
}

/*
   start: Interactive command loop.
   For commands that operate on the disk, an error is reported if the disk is not mounted/formatted.
   On exit, if the disk is still mounted, confirmation is requested.
*/
let start() be {
  let word, param1, param2, answer;
  word = vec(20);
  param1 = vec(20);
  param2 = vec(20);
  answer = vec(10);
  while true do {
    out("> ");
    ins(word, 20);
    if strcmp(word, "help") = 0 then
      help()
    else if strcmp(word, "format") = 0 then
      format()
    else if strcmp(word, "mount") = 0 then
      mount()
    else if strcmp(word, "dismount") = 0 then
      dismount()
    else if strcmp(word, "exit") = 0 then {
      if fsMounted = 1 then {
        out("Disk is still mounted. Confirm exit? (y/n): ");
        ins(answer, 10);
        if strcmp(answer, "y") <> 0 then continue
      }
      break
    }
    else if strcmp(word, "make") = 0 then {
      if fsMounted = 0 then {
        out("Error: Disk not mounted or formatted\n");
        continue
      }
      ins(param1, 20);
      make(param1)
    }
    else if strcmp(word, "show") = 0 then {
      if fsMounted = 0 then {
        out("Error: Disk not mounted or formatted\n");
        continue
      }
      ins(param1, 20);
      show(param1)
    }
    else if strcmp(word, "import") = 0 then {
      if fsMounted = 0 then {
        out("Error: Disk not mounted or formatted\n");
        continue
      }
      ins(param1, 20);  /* Unix file name */
      ins(param2, 20);  /* Disk file name */
      importFile(param1, param2)
    }
    else if strcmp(word, "export") = 0 then {
      if fsMounted = 0 then {
        out("Error: Disk not mounted or formatted\n");
        continue
      }
      ins(param1, 20);  /* Disk file name */
      ins(param2, 20);  /* Unix file name */
      exportFile(param1, param2)
    }
    else if strcmp(word, "status") = 0 then {
      if fsMounted = 0 then {
        out("Error: Disk not mounted or formatted\n");
        continue
      }
      status()
    }
    else {
      out("Unknown command: %s\n", word)
    }
  }
}
