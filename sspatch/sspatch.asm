	mcopy	sspatch.mac

SSPatch	start

	phb
	phk
	plb

	ph4	#statusbuf
	jsl	_GetStatus
	cmp	#0
	bne	GoInvalidROM

	lda	statusbuf+6
	and	#$FF
	cmp	#$14
	beq	patch_second_sight
GoInvalidROM anop
	brl	InvalidROM

patch_second_sight anop
; code to patch upload_data
	ldx	#0
	short	m
patch	lda	patchdata,x
	beq	endpatch
	sta	>$000400,x
	inx
	bra	patch
endpatch	long	m

	ldy	#10
	ldx	#$FFFF
delay	dex
	bne	delay
	dey
	bne	delay

	ph2	#$0400	; Address
	ph2	#$00	; BBR
	ph2	#$C2	; CBAR (must be x2)
	ph2	#$00	; CBR
	jsl	_RunCode
; finished base patch

	~WriteCString #appliedmsg

; secondary patch #1: fix mode 0x13 - change OAK mode select register ($21) value from $04 (Oak packed pixels) to $00 (VGA)
	ph4	#Mode13Patch1	; Source
	ph4	#1	; Length
	ph4	#$0DC4	; Destination
	ph2	#0	; Code
	jsl	_UploadData
	ph4	#Mode13Patch2	; Source
	ph4	#1	; Length
	ph4	#$C0EA	; Destination
	ph2	#0	; Code
	jsl	_UploadData

; verify patch
	ph4	#statusbuf
	jsl	_GetStatus
	cmp	#0
	bne	verify_fail

	lda	statusbuf+6
	and	#$FF
	cmp	#$15
	bne	verify_fail

verify_ok anop
	~WriteCString #verifiedmsg
	plb
	rtl

verify_fail anop
	~WriteCString #badpatchmsg
	plb
	rtl

InvalidROM anop
	short	m
	lda	statusbuf+6
	lsr	a
	lsr	a
	lsr	a
	lsr	a
	clc
	adc	#'0'
	sta	invalidrommsg+12
	lda	statusbuf+6
	and	#$0F
	adc	#'0'
	sta	invalidrommsg+14
	long	m
	~WriteCString #invalidrommsg
	plb
	rtl

statusbuf      ds 16
invalidrommsg  dc c'ROM version x.x detected.',h'0D',c'This utility can only patch ROM version 1.4 - patching aborted.',h'0D00'
appliedmsg     dc c'Applied patch to ROM.',h'0D00'
verifiedmsg    dc c'Patch verification was successful.',h'0D00'
badpatchmsg    dc c'Patch verification failed.',h'0D00'

patchdata      dc h'3E113248133E1532A911C900'

Mode13Patch1   dc h'00'
Mode13Patch2   dc h'00'

	end
