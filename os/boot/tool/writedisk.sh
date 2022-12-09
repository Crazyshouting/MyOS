CCPATH=/home/zzx/project/MyOS/MyOS/os/boot
dd if=$CCPATH/mbr.bin of=/home/zzx/os/bochs/hd60M.img bs=512 count=1 conv=notrunc
dd if=$CCPATH/loader.bin of=/home/zzx/os/bochs/hd60M.img bs=512 count=3 seek=2 conv=notrunc
#dd if=$CCPATH/kernel/kernel.bin of=/home/zzx/os/bochs/hd60M.img bs=512 count=200 seek=9 conv=notrunc
