iix assemble sspatch.asm keep=obj:sspatch
iix link obj:sspatch ..:sslib:obj:sslib keep=sspatch
