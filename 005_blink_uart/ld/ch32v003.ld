/*
  LD script for the CH32V003 microcontroller.
*/

MEMORY
{
  FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 16K
  RAM   (xrw) : ORIGIN = 0x20000000, LENGTH = 2K
}

SECTIONS
{
  .init :
  {
    KEEP(*(.init*))
  } > FLASH

  .text :
  {
     *(.text*)
  } > FLASH

  .rodata_str :
  {
     *(.rodata.str*)
  } > FLASH

  .data :
  {
     __data_start = .;
     *(.sdata*)
     *(.data*)
     *(.rodata*)
     __data_end = .;
  } > RAM AT> FLASH

  .bss (NOLOAD) :
  {
      __bss_start = .;
      *(.bss*)
      *(.sbss*)
      __bss_end = .;
  } > RAM

  __data_load_start = LOADADDR(.data);
  __end_of_stack = ORIGIN(RAM) + LENGTH(RAM);
  PROVIDE(__global_pointer$ = __data_start + 0x800);
}
