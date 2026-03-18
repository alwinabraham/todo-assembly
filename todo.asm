global _start

section .data

header db "HTTP/1.1 200 OK",13,10
       db "Content-Type: text/html; charset=utf-8",13,10
       db "Connection: close",13,10,13,10
header_len equ $-header

redirect db "HTTP/1.1 302 Found",13,10
         db "Location: /",13,10
         db "Connection: close",13,10,13,10
redirect_len equ $-redirect

html_top db "<html><body>",10
         db "<h1>Assembly Todo</h1>",10
         db "<form action='/add'>",10
         db "<input name='task'>",10
         db "<button>Add</button>",10
         db "</form><pre>",10
html_top_len equ $-html_top

html_bottom db "</pre>",10
            db "<a href='/del'><button>Clear</button></a>",10
            db "</body></html>"
html_bottom_len equ $-html_bottom

link_prefix db " <a href='/del?n="
link_prefix_len equ 17
link_suffix db "'>X</a>"
link_suffix_len equ 7

done_prefix db " <a href='/done?n="
done_prefix_len equ 18
done_suffix db "'>"
            db 0E2h,09Ch,093h
            db "</a>",10
done_suffix_len equ 10

filename db "todos.txt",0

sockaddr:
    dw 2
    dw 0x711A
    dd 0
    dq 0

section .bss

sock resq 1
client resq 1
fd resq 1

req resb 1024
req_len resq 1
buffer resb 2048
out_buffer resb 4096
line_index resq 1
del_line_num resq 1

section .text

_start:

; socket
mov rax,41
mov rdi,2
mov rsi,1
mov rdx,0
syscall
mov [sock],rax

; bind
mov rax,49
mov rdi,[sock]
mov rsi,sockaddr
mov rdx,16
syscall

; listen
mov rax,50
mov rdi,[sock]
mov rsi,10
syscall

accept_loop:

; accept
mov rax,43
mov rdi,[sock]
mov rsi,0
mov rdx,0
syscall
mov [client],rax

; read request
mov rax,0
mov rdi,[client]
mov rsi,req
mov rdx,1024
syscall
mov [req_len],rax

; check /add (path is "GET /add..." so first path char is at req+5)
cmp byte [req+5],'a'
je add_task

; check /del or /done (both start with 'd')
cmp byte [req+5],'d'
jne show_page
cmp byte [req+6],'e'
je clear_tasks
cmp byte [req+6],'o'
je mark_done

jmp show_page

add_task:

; open file append
mov rax,2
mov rdi,filename
mov rsi,1089          ; O_WRONLY | O_CREAT | O_APPEND
mov rdx,0644
syscall
mov [fd],rax

; write initial status flag "0 " (not completed)
mov byte [buffer],'0'
mov rax,1
mov rdi,[fd]
mov rsi,buffer
mov rdx,1
syscall
mov byte [buffer],' '
mov rax,1
mov rdi,[fd]
mov rsi,buffer
mov rdx,1
syscall

; find start of task string (don't search past end of request)
mov rsi,req
mov rcx,[req_len]
add rcx,req

find_task:
cmp rsi,rcx
jae redirect_home
cmp byte [rsi],'t'
jne next_char
cmp byte [rsi+1],'a'
jne next_char
cmp byte [rsi+2],'s'
jne next_char
cmp byte [rsi+3],'k'
jne next_char
cmp byte [rsi+4],'='
jne next_char

add rsi,5
jmp copy_task

next_char:
inc rsi
jmp find_task

copy_task:
; rcx is clobbered by syscall, so reload end-of-request pointer each iteration
mov rcx,[req_len]
add rcx,req
cmp rsi,rcx
jae finish_task
mov al,[rsi]

cmp al,' '
je finish_task
cmp al,'&'
je finish_task
cmp al,13
je finish_task
cmp al,10
je finish_task

cmp al,'+'
jne normal_char
mov al,' '

normal_char:
mov [buffer],al

mov r8,rsi
mov rax,1
mov rdi,[fd]
mov rsi,buffer
mov rdx,1
syscall
mov rsi,r8

inc rsi
jmp copy_task

finish_task:

mov byte [buffer],10

mov rax,1
mov rdi,[fd]
mov rsi,buffer
mov rdx,1
syscall

; close file
mov rax,3
mov rdi,[fd]
syscall

jmp redirect_home

; ----------------
; CLEAR TODOS (all) or DELETE ONE LINE (/del?n=N)
; ----------------

clear_tasks:
; look for "n=" in request
mov rsi,req
mov rcx,[req_len]
add rcx,req
.find_n:
cmp rsi,rcx
jae clear_all
cmp byte [rsi],'n'
jne .next_n
cmp byte [rsi+1],'='
jne .next_n
add rsi,2
jmp parse_line_num
.next_n:
inc rsi
jmp .find_n

parse_line_num:
xor r11,r11
.parse_digit:
cmp rsi,rcx
jae do_delete_one
mov al,[rsi]
cmp al,'0'
jb do_delete_one
cmp al,'9'
ja do_delete_one
imul r11,10
sub al,'0'
movzx rax,al
add r11,rax
inc rsi
jmp .parse_digit

do_delete_one:
mov [del_line_num],r11
; read file
mov rax,2
mov rdi,filename
mov rsi,64
mov rdx,0644
syscall
mov [fd],rax
mov rax,0
mov rdi,[fd]
mov rsi,buffer
mov rdx,2048
syscall
mov rbx,rax
mov rax,3
mov rdi,[fd]
syscall
; build out_buffer without line del_line_num
mov r8,[del_line_num]
mov rsi,buffer
mov rdi,out_buffer
mov r9,buffer
add r9,rbx
xor r10,r10
.del_line_loop:
cmp rsi,r9
jae .del_write_back
cmp r10,r8
jne .del_copy_line
.del_skip_line:
cmp rsi,r9
jae .del_write_back
mov al,[rsi]
inc rsi
cmp al,10
jne .del_skip_line
inc r10
jmp .del_line_loop
.del_copy_line:
cmp rsi,r9
jae .del_write_back
mov al,[rsi]
cmp al,10
je .del_end_line
cmp al,13
je .del_end_line
mov [rdi],al
inc rsi
inc rdi
jmp .del_copy_line
.del_end_line:
cmp rsi,r9
jae .del_next_ln
mov al,[rsi]
cmp al,10
je .del_skip_nl
cmp al,13
je .del_skip_nl
jmp .del_next_ln
.del_skip_nl:
inc rsi
.del_next_ln:
mov byte [rdi],10
inc rdi
inc r10
jmp .del_line_loop
.del_write_back:
mov r13,rdi
sub r13,out_buffer
mov rax,2
mov rdi,filename
mov rsi,577
mov rdx,0644
syscall
mov [fd],rax
mov rax,1
mov rdi,[fd]
mov rsi,out_buffer
mov rdx,r13
syscall
mov rax,3
mov rdi,[fd]
syscall
jmp redirect_home

; ----------------
; MARK TODO AS DONE/UNDONE: /done?n=N
; ----------------

mark_done:
; look for "n=" in request
mov rsi,req
mov rcx,[req_len]
add rcx,req
.find_n_done:
cmp rsi,rcx
jae redirect_home
cmp byte [rsi],'n'
jne .next_n_done
cmp byte [rsi+1],'='
jne .next_n_done
add rsi,2
jmp .parse_line_num_done
.next_n_done:
inc rsi
jmp .find_n_done

.parse_line_num_done:
xor r11,r11
.parse_digit_done:
cmp rsi,rcx
jae .have_line_num_done
mov al,[rsi]
cmp al,'0'
jb .have_line_num_done
cmp al,'9'
ja .have_line_num_done
imul r11,10
sub al,'0'
movzx rax,al
add r11,rax
inc rsi
jmp .parse_digit_done

.have_line_num_done:
mov [del_line_num],r11
; read file
mov rax,2
mov rdi,filename
mov rsi,64
mov rdx,0644
syscall
mov [fd],rax
mov rax,0
mov rdi,[fd]
mov rsi,buffer
mov rdx,2048
syscall
mov rbx,rax
mov rax,3
mov rdi,[fd]
syscall
; toggle status flag on the selected line in-place
mov r8,[del_line_num]
mov rsi,buffer
mov r9,buffer
add r9,rbx
xor r10,r10
.toggle_loop:
cmp rsi,r9
jae .write_back_done
cmp r10,r8
jne .skip_toggle_line
; rsi at start of line: first char is status flag
cmp byte [rsi],'0'
jne .set_zero_flag
mov byte [rsi],'1'
jmp .after_toggle_flag
.set_zero_flag:
mov byte [rsi],'0'
.after_toggle_flag:
.skip_toggle_line:
; advance to next line
.next_char_done:
cmp rsi,r9
jae .write_back_done
mov al,[rsi]
inc rsi
cmp al,10
jne .next_char_done
inc r10
jmp .toggle_loop
.write_back_done:
; write modified buffer back to file
mov rax,2
mov rdi,filename
mov rsi,577
mov rdx,0644
syscall
mov [fd],rax
mov rax,1
mov rdi,[fd]
mov rsi,buffer
mov rdx,rbx
syscall
mov rax,3
mov rdi,[fd]
syscall
jmp redirect_home

clear_all:
mov rax,2
mov rdi,filename
mov rsi,577
mov rdx,0644
syscall
mov [fd],rax

mov rax,3
mov rdi,[fd]
syscall

jmp redirect_home

; ----------------

redirect_home:

mov rax,1
mov rdi,[client]
mov rsi,redirect
mov rdx,redirect_len
syscall

jmp close_conn

; ----------------
; SHOW PAGE
; ----------------

show_page:

; send header
mov rax,1
mov rdi,[client]
mov rsi,header
mov rdx,header_len
syscall

; html top
mov rax,1
mov rdi,[client]
mov rsi,html_top
mov rdx,html_top_len
syscall

; open todos file (O_RDONLY|O_CREAT so file is created if missing)
mov rax,2
mov rdi,filename
mov rsi,64
mov rdx,0644
syscall
mov [fd],rax

; read file
mov rax,0
mov rdi,[fd]
mov rsi,buffer
mov rdx,2048
syscall
mov rbx,rax

; close file
mov rax,3
mov rdi,[fd]
syscall

; build output: each line + " <a href='/del?n=XX'>X</a>\n"
mov rsi,buffer
mov rdi,out_buffer
mov r8,buffer
add r8,rbx
xor r10,r10
.line_loop:
cmp rsi,r8
jae .lines_done
.start_line:
; read status flag ('0' or '1') and optional space
mov al,[rsi]
mov bl,al
inc rsi
cmp byte [rsi],' '
jne .no_flag_space
inc rsi
.no_flag_space:
; write visual checkbox prefix based on flag
mov byte [rdi],'['
inc rdi
cmp bl,'1'
je .mark_x
mov byte [rdi],' '
jmp .mark_after
.mark_x:
mov byte [rdi],'x'
.mark_after:
inc rdi
mov byte [rdi],']'
inc rdi
mov byte [rdi],' '
inc rdi
.copy_line:
cmp rsi,r8
jae .line_done
mov al,[rsi]
cmp al,10
je .line_done
cmp al,13
je .line_done
mov [rdi],al
inc rsi
inc rdi
jmp .copy_line
.line_done:
; skip newline
cmp rsi,r8
jae .output_link
mov al,[rsi]
cmp al,10
je .skip_nl
cmp al,13
je .skip_nl
jmp .output_link
.skip_nl:
inc rsi
jmp .output_link
.output_link:
; link_prefix
mov rcx,link_prefix_len
mov r11,link_prefix
.copy_prefix:
mov al,[r11]
mov [rdi],al
inc r11
inc rdi
dec rcx
jnz .copy_prefix
; two-digit line number (r10)
mov rax,r10
xor rdx,rdx
mov r11,10
div r11
add al,'0'
add dl,'0'
mov [rdi],al
mov [rdi+1],dl
add rdi,2
; link_suffix
mov rcx,link_suffix_len
mov r11,link_suffix
.copy_suffix:
mov al,[r11]
mov [rdi],al
inc r11
inc rdi
dec rcx
jnz .copy_suffix

; done_prefix
mov rcx,done_prefix_len
mov r11,done_prefix
.copy_done_prefix:
mov al,[r11]
mov [rdi],al
inc r11
inc rdi
dec rcx
jnz .copy_done_prefix
; two-digit line number (r10) reused
mov rax,r10
xor rdx,rdx
mov r11,10
div r11
add al,'0'
add dl,'0'
mov [rdi],al
mov [rdi+1],dl
add rdi,2
; done_suffix
mov rcx,done_suffix_len
mov r11,done_suffix
.copy_done_suffix:
mov al,[r11]
mov [rdi],al
inc r11
inc rdi
dec rcx
jnz .copy_done_suffix

inc r10
jmp .line_loop
.lines_done:
mov r13,rdi
sub r13,out_buffer

; send todos (with delete links)
mov rax,1
mov rdi,[client]
mov rsi,out_buffer
mov rdx,r13
syscall

; html bottom
mov rax,1
mov rdi,[client]
mov rsi,html_bottom
mov rdx,html_bottom_len
syscall

close_conn:

mov rax,3
mov rdi,[client]
syscall

;         ∧＿∧
;     ;;（´・ω・）
;   ＿旦_(っ.|🍺|)＿＿ 
;   |l￣l||￣しﾞしﾞ￣| 
; Did this much with the support and chatgpt.
; Will update the ui if i didnt get the job after 2 mnths

jmp accept_loop