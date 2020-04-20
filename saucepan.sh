#!/bin/bash

usage()
{
    echo
    echo "USAGE:"
    echo "`basename $0` [--core <core_name>|--stock-core <stock_core>] <game_name> <rom_name>"
    echo
    echo "  --core <core_name>"
    echo "      Use the custom core named <core_name> located in your resources/cores directory."
    echo
    echo "  --stock-core <stock_core>"
    echo "      Use a built-in ALU core. This will make your UCE file substantially smaller."
    echo "      <stock_core> must be genesis, mame2003plus, mame2010, nes, snes, or atari2600."
    echo
    echo "  <game_name>"
    echo "      Specifies the name you want to appear on the ALU Add-On menu."
    echo "      Be sure to put the name in quotation marks if it has spaces in it."
    echo
    echo "  <rom_name>"
    echo "      Specifies the base name of a ROM file in the resources/roms directory."
    echo "      Note that you should not include the file extension."
    echo "      If you have a custom box art and/or bezel, they should be located at"
    echo "          resources/boxart/<rom_name>.png and resources/bezels/<rom_name>.png respectively."
    echo
}

# Built-in cores located in /emulator on the ALU file system
stock_core_genesis=genesis_plus_gx_libretro.so
stock_core_mame2003plus=mame2003_plus_libretro.so
stock_core_mame2010=mame2010_libretro.so
stock_core_nes=quicknes_libretro.so
stock_core_snes=snes_mtfaust-arm64-cortex-a53.so
stock_core_atari2600=stella_libretro.so

# The core to use if none are specified on the command line
default_core_name=mame2003_plus_libretro.so

# Where the script lives
script_dir=`dirname $0`

# Location of the various files that will be pulled in to create a UCE
src_dir_bezels="${script_dir}/resources/bezels"
src_dir_boxart="${script_dir}/resources/boxart"
src_dir_cores="${script_dir}/resources/cores"
src_dir_roms="${script_dir}/resources/roms"

# Default box art and bezel files
default_boxart="${script_dir}/defaults/boxart.png"
default_bezel="${script_dir}/defaults/bezel.png"

core_name=""
use_stock_core=false

# Parse out command-line options
positional_args=""
while (( "$#" ))
do
    case "$1" in
        -h)
            usage
            exit 0
            ;;
        -c|--core)
            if [ "$core_name" != "" ]
            then
                echo "ERROR: Multiple cores specified on the command line"
                exit 1
            else
                core_name="$2"
            fi
            shift 2
            ;;
        -s|--stock-core)
            if [ "$core_name" != "" ]
            then
                echo "ERROR: Multiple cores specified on the command line"
                exit 1
            else
                case "$2" in
                    genesis)
                        core_name="${stock_core_genesis}"
                        ;;
                    mame2003plus)
                        core_name="${stock_core_mame2003plus}"
                        ;;
                    mame2010)
                        core_name="${stock_core_mame2010}"
                        ;;
                    nes)
                        core_name="${stock_core_nes}"
                        ;;
                    snes)
                        core_name="${stock_core_snes}"
                        ;;
                    atari2600)
                        core_name="${stock_core_atari2600}"
                        ;;
                    *)
                        echo "ERROR: There is no stock core associated with the name \"$2\""
                        exit 1
                        ;;
                esac
                use_stock_core=true
                shift 2
            fi
            ;;
        -*|--*) # unrecognized arguments
            echo "ERROR: Unrecognized argument $1"
            usage
            exit 1
            ;;
        *) # preserve positional arguments
            positional_args="${positional_args} \"$1\""
            shift
            ;;
    esac
done

# Put the positional arguments back in place so we can parse them
eval set -- "${positional_args}"

# Use the default core if none was specified
if [ "${core_name}" == "" ]
then
    core_name="${default_core_name}"
fi

# If using a custom core, make sure the file really exists before we proceed
if [ "${use_stock_core}" == "false" ]
then
    if [ ! -f "${src_dir_cores}/${core_name}" ]
    then
        echo "ERROR: Could not find custom core ${core_name} in ${src_dir_cores}"
        exit 1
    fi
fi

if [ "$1" == "" ]
then
    echo "ERROR: You need to specify a game name on the command line."
    exit 1
else
    game_name="$1"
fi

if [ "$2" == "" ]
then
    echo "ERROR: You need to specify a ROM name on the command line."
    exit 1
else
    rom_name="$2"
fi

# Verify a ROM really exists before we get in too deep.
# We assume there's only one file with the base rom_name in the roms directory.
# If there's more, there's a chance we'll grab the wrong one.
src_rom=`find ${src_dir_roms}/ -type f -name "${rom_name}.*" | head -1`
if [ -f "${src_rom}" ]
then
    echo "Found ROM file: ${src_rom}"
else
	echo "Could not locate ROM file for \"${rom_name}\". Exiting."
	exit 1
fi

# Replace any characters in the game name that are likely to confuse the file system.
sanitized_game_name=`echo "$1" | sed 's|[ :]|_|g'`

echo "Building \"${game_name}\" from \"${rom_name}\" sources..."

staging_dir=${script_dir}/AddOn_${sanitized_game_name}
mkdir -p ${staging_dir}/boxart
mkdir -p ${staging_dir}/emu
mkdir -p ${staging_dir}/roms
mkdir -p ${staging_dir}/save

# Pull in box art from the source dir. If none exists, use the default.
src_boxart=${src_dir_boxart}/${rom_name}.png
if [ -f "${src_boxart}" ]
then
	cp -p ${src_boxart} ${staging_dir}/boxart/boxart.png
else
    echo "Custom box art not found. Using default box art"
	cp -p ${default_boxart} ${staging_dir}/boxart/boxart.png
fi

# Pull in bezel from the source dir. If none exists, assume no bezel.
src_bezel=${src_dir_bezels}/${rom_name}.png
has_bezel=false
if [ -f "${src_bezel}" ]
then
	cp -p ${src_bezel} ${staging_dir}/boxart/addon.z.png
	has_bezel=true
elif [ -f "${default_bezel}" ]
then
    echo "Custom bezel not found. Using default bezel."
    cp -p ${default_bezel} ${staging_dir}/boxart/addon.z.png
    has_bezel=true
else
    echo "Not using a bezel"
fi

# Set up our emulator core.
if [ "${use_stock_core}" == "true" ]
then
    # No need to copy anything. The core is already on the ALU.
    core_path=/emulator/${core_name}
else
    cp -p ${src_dir_cores}/${core_name} ${staging_dir}/emu
    core_path=./emu/${core_name}
fi

# Pull in ROM from the source dir.
cp -p ${src_rom} ${staging_dir}/roms

ln -sf ${staging_dir}/boxart/boxart.png ${staging_dir}/title

cat ${script_dir}/defaults/cartridge.xml | sed "s|GAME_NAME|${game_name}|g" > ${staging_dir}/cartridge.xml

if [ "${has_bezel}" = true ]
then
	exec_src=${script_dir}/defaults/exec_bezel.sh
else
	exec_src=${script_dir}/defaults/exec.sh
fi

cat ${exec_src} | sed "s|CORE_PATH|${core_path}|g" | sed "s|ROM_NAME|${rom_name}.zip|g" > ${staging_dir}/exec.sh

# The staging area is built.  Now let's squash it!
${script_dir}/build_sq_cartridge_pack.sh ${staging_dir} ${script_dir}/AddOn_${sanitized_game_name}.UCE

# And clean up after ourselves
rm -r ${staging_dir}