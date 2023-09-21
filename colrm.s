* colrm - remove columns on each input line
*
* Itagaki Fumihiko 24-Jan-95  Create.
* 1.0
*
* Usage: colrm [ -BCZ ] <startcol> [ <endcol> ]

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref atou
.xref strlen
.xref strfor1
.xref strip_excessive_slashes

STACKSIZE	equ	2048

READ_MAX_TO_OUTPUT_TO_COOKED	equ	8192
INPBUFSIZE_MIN	equ	258
OUTBUF_SIZE	equ	8192

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_B		equ	0	*  -B
FLAG_C		equ	1	*  -C
FLAG_Z		equ	2	*  -Z
FLAG_eof	equ	3

.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	bss_top(pc),a6
		lea	stack_bottom(a6),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin(a6)
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		moveq	#0,d6				*  D6.W : エラー・コード
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.L : フラグ
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		tst.b	1(a0)
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		cmp.b	#'B',d0
		beq	option_B_found

		cmp.b	#'C',d0
		beq	option_C_found

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

option_B_found:
		bclr	#FLAG_C,d5
		bset	#FLAG_B,d5
		bra	set_option_done

option_C_found:
		bclr	#FLAG_B,d5
		bset	#FLAG_C,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
		subq.l	#1,d7
		blo	too_few_args

		bsr	atou
		bne	bad_arg

		tst.b	(a0)+
		bne	bad_arg

		move.l	d1,startcol(a6)
		beq	bad_arg

		moveq	#-1,d1
		subq.l	#1,d7
		blo	endcol_ok
		bhi	too_many_args

		bsr	atou
		bne	bad_arg

		tst.b	(a0)+
		bne	bad_arg

		cmp.l	startcol(a6),d1
		blo	bad_arg
endcol_ok:
		move.l	d1,endcol(a6)
		beq	bad_arg
	*
		moveq	#1,d0				*  出力は
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering(a6)
		beq	input_max			*  -- block device

		*  character device
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	input_max

		*  cooked character device
		move.l	#READ_MAX_TO_OUTPUT_TO_COOKED,d0
		btst	#FLAG_B,d5
		bne	inpbufsize_ok

		bset	#FLAG_C,d5			*  改行を変換する
		bra	inpbufsize_ok

input_max:
		move.l	#$00ffffff,d0
inpbufsize_ok:
		move.l	d0,read_size(a6)
		*  出力バッファを確保する
		tst.b	do_buffering(a6)
		beq	outbuf_ok

		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free(a6)
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outbuf_top(a6)
		move.l	d0,outbuf_ptr(a6)
outbuf_ok:
		*  入力バッファを確保する
		move.l	#$00ffffff,d0
		bsr	malloc
		sub.l	#$81000000,d0
		cmp.l	#INPBUFSIZE_MIN,d0
		blo	insufficient_memory

		move.l	d0,inpbuf_size(a6)
		bsr	malloc
		bmi	insufficient_memory
inpbuf_ok:
		move.l	d0,inpbuf_top(a6)
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin(a6)
		bmi	open_file_failure

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
	*
	*  開始
	*
		bsr	colrm
		bsr	flush_outbuf
exit_program:
		move.l	stdin(a6),d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
exit_program_1:
		move.w	d6,-(a7)
		DOS	_EXIT2

open_file_failure:
		lea	msg_open_fail(pc),a0
		bsr	werror_myname_and_msg
		moveq	#2,d6
		bra	exit_program_1

too_many_args:
		lea	msg_too_many_args(pc),a0
		bra	werror_usage

too_few_args:
		lea	msg_too_few_args(pc),a0
		bra	werror_usage

bad_arg:
		lea	msg_bad_arg(pc),a0
werror_usage:
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program
****************************************************************
colrm_done:
		rts

colrm:
		btst	#FLAG_Z,d5
		sne	terminate_by_ctrlz(a6)
		sf	terminate_by_ctrld(a6)
		bsr	is_chrdev
		beq	colrm_start			*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	colrm_start

		st	terminate_by_ctrlz(a6)
		st	terminate_by_ctrld(a6)
colrm_start:
		bclr	#FLAG_eof,d5
		move.l	inpbuf_top(a6),inpbuf_ptr(a6)
		clr.l	inpbuf_remain(a6)
colrm_loop:
		moveq	#0,d3				*  D3.L : column counter
colrm_loop_0:
		bsr	getc
colrm_loop_1:
		bmi	colrm_done

		sf	d2
		cmp.b	#LF,d0
		beq	colrm_newline

		cmp.b	#CR,d0
		bne	colrm_not_cr

		st	d2
		move.l	d0,d1
		bsr	getc
		exg	d0,d1
		bmi	colrm_not_cr

		cmp.b	#LF,d1
		beq	colrm_crlf
colrm_not_cr:
		addq.l	#1,d3
		cmp.l	startcol(a6),d3
		blo	colrm_putc

		cmp.l	endcol(a6),d3
		bls	colrm_continue
colrm_putc:
		bsr	putc
colrm_continue:
		tst.b	d2
		beq	colrm_loop_0

		move.l	d1,d0
		bra	colrm_loop_1

colrm_newline:
		btst	#FLAG_C,d5
		beq	output_lf
colrm_crlf:
		moveq	#CR,d0
		bsr	putc
output_lf:
		moveq	#LF,d0
		bsr	putc
		bra	colrm_loop
*****************************************************************
getc:
		movem.l	d3/a3,-(a7)
		movea.l	inpbuf_ptr(a6),a3
		move.l	inpbuf_remain(a6),d3
		bne	getc_get1

		btst	#FLAG_eof,d5
		bne	getc_eof

		move.l	inpbuf_top(a6),d0
		add.l	inpbuf_size(a6),d0
		sub.l	a3,d0
		bne	getc_read

		movea.l	inpbuf_top(a6),a3
		move.l	inpbuf_size(a6),d0
getc_read:
		cmp.l	read_size(a6),d0
		bls	getc_read_1

		move.l	read_size(a6),d0
getc_read_1:
		move.l	d0,-(a7)
		move.l	a3,-(a7)
		move.l	stdin(a6),d0
		move.w	d0,-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,d3
		bmi	read_fail

		tst.b	terminate_by_ctrlz(a6)
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc
trunc_ctrlz_done:
		tst.b	terminate_by_ctrld(a6)
		beq	trunc_ctrld_done

		moveq	#CTRLD,d0
		bsr	trunc
trunc_ctrld_done:
		tst.l	d3
		beq	getc_eof
getc_get1:
		subq.l	#1,d3
		moveq	#0,d0
		move.b	(a3)+,d0
getc_done:
		move.l	a3,inpbuf_ptr(a6)
		move.l	d3,inpbuf_remain(a6)
		movem.l	(a7)+,d3/a3
		tst.l	d0
		rts

getc_eof:
		bset	#FLAG_eof,d5
		moveq	#-1,d0
		bra	getc_done

read_fail:
		lea	msg_read_fail(pc),a0
		bra	werror_exit_3
*****************************************************************
trunc:
		movem.l	d1/a0,-(a7)
		move.l	d3,d1
		beq	trunc_done

		movea.l	a3,a0
trunc_find_loop:
		cmp.b	(a0)+,d0
		beq	trunc_found

		subq.l	#1,d1
		bne	trunc_find_loop
		bra	trunc_done

trunc_found:
		move.l	a0,d3
		subq.l	#1,d3
		sub.l	a3,d3
		bset	#FLAG_eof,d5
trunc_done:
		movem.l	(a7)+,d1/a0
		rts
*****************************************************************
flush_outbuf:
		move.l	d0,-(a7)
		tst.b	do_buffering(a6)
		beq	flush_return

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free(a6),d0
		beq	flush_return

		move.l	d0,-(a7)
		move.l	outbuf_top(a6),-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		blo	write_fail

		move.l	outbuf_top(a6),d0
		move.l	d0,outbuf_ptr(a6)
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free(a6)
flush_return:
		move.l	(a7)+,d0
		rts
*****************************************************************
putc:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering(a6)
		bne	putc_buffering

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail
		bra	putc_done

putc_buffering:
		tst.l	outbuf_free(a6)
		bne	putc_buffering_1

		bsr	flush_outbuf
putc_buffering_1:
		movea.l	outbuf_ptr(a6),a0
		move.b	d0,(a0)+
		move.l	a0,outbuf_ptr(a6)
		subq.l	#1,outbuf_free(a6)
putc_done:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
insufficient_memory:
		lea	msg_no_memory(pc),a0
		bra	werror_exit_3
*****************************************************************
write_fail:
		lea	msg_write_fail(pc),a0
werror_exit_3:
		bsr	werror_myname_and_msg
		moveq	#3,d6
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
is_chrdev:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## colrm 1.0 ##  Copyright(C)1995 by Itagaki Fumihiko',0

msg_myname:			dc.b	'colrm: ',0
msg_no_memory:			dc.b	'メモリが足りません',CR,LF,0
msg_bad_arg:			dc.b	'引数が正しくありません',0
msg_too_few_args:		dc.b	'引数が足りません',0
msg_too_many_args:		dc.b	'引数が多過ぎます',0
msg_start_column_not_specified:	dc.b	'開始カラム番号が指定されていません',CR,LF,0
msg_start_column_less_than_1:	dc.b	'開始カラム番号が 1未満です',CR,LF,0
msg_open_fail:			dc.b	'標準入力をオープンできません',CR,LF,0
msg_read_fail:			dc.b	'入力エラー',CR,LF,0
msg_write_fail:			dc.b	'出力エラー',CR,LF,0
msg_illegal_option:		dc.b	'不正なオプション -- ',0
msg_usage:			dc.b	CR,LF
	dc.b	'使用法:  colrm [-BCZ] <開始カラム番号> [<終了カラム番号>]',CR,LF,0
*****************************************************************
.bss
.even
bss_top:

.offset 0
stdin:			ds.l	1
inpbuf_top:		ds.l	1
inpbuf_size:		ds.l	1
inpbuf_ptr:		ds.l	1
inpbuf_remain:		ds.l	1
outbuf_top:		ds.l	1
outbuf_ptr:		ds.l	1
outbuf_free:		ds.l	1
read_size:		ds.l	1
list_top:		ds.l	1
startcol:		ds.l	1
endcol:			ds.l	1
do_buffering:		ds.b	1
terminate_by_ctrlz:	ds.b	1
terminate_by_ctrld:	ds.b	1

.even
			ds.b	STACKSIZE
.even
stack_bottom:

.bss
		ds.b	stack_bottom
*****************************************************************

.end start
