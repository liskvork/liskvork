liskvork(1)

# NAME

**liskvork** - Modern multi-platform gomoku game server 

# SYNOPSIS

**liskvork** [**-c**|**-\-config path**] [**-\-player1** *path*] [**-\-player2** *path*] [**-s**|**-\-size** *size*] [**-m**|**-\-memory** *mem*] [**-r**|**-\-replay-file** *path*] [**-\-no-replay**] [**-\-o**|**-\-output** *path*]
**liskvork** **-h**|**--help**
**liskvork -\-init-config**

# DESCRIPTION

**liskvork** is a modern game server to make AIs fight on a gomoku board. liskvork starts two brain executables and orchestrates the exchange between the two as well as enforce the rules of the game. By default if no **config.ini** file is found, liskvork will prompt the user to run with the **--init-config** flag. 
This will generate the default config in the current working directory. This configuration file will need to be edited in order to use liskvork properly.

# OPTIONS

**-h**, **-\-help**
:  Displays the help for the command

**-\-init-config**
:  Creates a default config file or resets the **config.ini** file to default value.

**-c**, **-\-config** *path*
:  Use another file as configuration

**-\-player1** *path*
:  Override the path for the player1

**-\-plauer2** *path*
:  Override the path for the player2

**-s**, **-\-size**
:  Set the size of the board (N\*N) for the game

**-m**, **-\-memory**
:  Set the maximum allocated memory for each brains

**-r**, **-\-replay-file**
:  Set the output file for the game replay

**-\-no-replay**
:  Toggle the replay file output

**-o**, **-\-output**
:  Set the output file for the real-time board 

# CONFIGURATION
**liskvork** needs a configuration file to work properly. Although it can be overriden with command line arguments, every other configuration keys will be loaded from the specified file.

## GAME CONFIGURATION
Should be listed under the [game] tag

**board_size**
:  Define the board size (N\*N) for the game

**max_memory**
:  Define the maximum allocated memory for each brains

## PLAYER CONFIGURATION
Should be listed under both [player1] **AND** [player2] tags

**path**
:  Define the path to the brain executable

**timeout_match**
:  Define the maximum amount of play time allowed for the brain

**timeout_turn**
:  Define the maximum amount of time the brain can take each turn

## LOG CONFIGURATION KEYS
Should be listed under the [log] tag

**level**
:  Set the logger level

**board_file**
:  Set a file output for the real-time board

**board_color**
:  Set whether the board should be colored or not

**replay_file**
:  Set a file output for the game replay

## OTHER CONFIGURATION KEYS
Should be listed under the [other] tag

**auto_start**
:  Set whether the game should start automatically

**auto_close**
:  Set whether **liskvork** should exit upon ending the game

**end_grace_time**
:  Set the amount of time a brain has to properly close before getting killed

