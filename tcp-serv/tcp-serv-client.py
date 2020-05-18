import socket
import sys
import time

PORT = 51574
TIMEOUT = 4

if len(sys.argv) < 2:
    print('[^] You need to supply at least 1 argument - the ip of server')
    print('[^] If you supply a second argument, it will be used instead of the default port')
    exit(0)

IP = sys.argv[1]

if len(sys.argv) > 2:
    PORT = int(sys.argv[2])

options = {'recv': 0, 'read': 0, 'send': 1, 'write': 1, 'shell': 2, 'exit': 3}

#password = input('[-] Please enter the password for the server: ', end='')
password = 't7/]'
print('[+] Using password %s' % password)

def getSock(cmd):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
    sock.settimeout(TIMEOUT)
    try:
        sock.connect((IP, PORT))
    except Exception as e:
        print('[^] Error during connecting: %s' % str(e))
        sock.close()
        return None
    print ('[+] Connected to %s:%d' %(IP, PORT))
    try:
        sock.send(password.encode() + b'\n')
        time.sleep(0.3) # to avoid screwing up the password
        sock.send(cmd)
    except Exception as e:
        print('[^] Error during authenticating and sending command: %s' % str(e))
        sock.close()
        return None
    return sock
         

while True:
    print ('\n\n[-] What would you like to do? ("recv"/"read" file, "send"/"write", get interactive "shell", "exit"):')
    choice = input()
    while choice not in options:
        print('[-] Invalid choice. Enter valid option:')
        choice = input()
    tchoice = options[choice]
    if tchoice < 2:
        print('[-] What file would you like to %s?' % choice)
        filepath = input()
        if tchoice == 0:
            print('[-] Where do you want to output this file locally? ("-" for stdout)')
            location = input()
            if location != "-":
                try:
                    file = open(location, 'wb')
                except Exception as e:
                    print('[^] Error during opening file: %s' % str(e))
            sock = getSock(b'fr\n')
            if not sock:
                continue
            time.sleep(0.3) # so that the server doesn't mess up the command
            try:
                sock.send(filepath.encode() + b'\n')
            except Exception as e:
                print('[^] Error during sending filename: %s' % str(e))
                continue
            print('[+] Receiving data from server file %s...' % filepath)
            time.sleep(0.3) # so that the server doesn't mess up the filename
            try:
                while True:
                    part = sock.recv(4096)
                    if not part:
                        break
                    if location != "-":
                        file.write(part)
                    else:
                        print(part)
            except Exception as e:
                sock.close()
                print('[^] Error during receiving file: %s' % str(e))
                continue
            if location != "-":
                file.close()
            print('[+] Successfully received data!')
        else:
            print('[-] Where do you want to save this file on the server?')
            serv_filepath = input()
            try:
                file = open(filepath, 'rb').read()
            except Exception as e:
                print('[^] Error during reading local file: %s' % str(e))
                continue
            sock = getSock(b'fw\n')
            if not sock:
                continue
            time.sleep(0.3) # so that the server doesn't mess up the command
            try:
                sock.send(serv_filepath.encode() + b'\n')
            except Exception as e:
                print('[^] Error during sending filename: %s' % str(e))
                continue
            print ('[+] Sending file %s...' % filepath)
            time.sleep(0.3) # so that the server doesn't mess up the filename
            try:
                sock.sendall(file)
                sock.close()
            except Exception as e:
                sock.close()
                print('[^] Error during sending file: %s' % str(e))
                continue     
            print('[+] Successfully sent the file! (at least it seemed so, check the server)')
    if tchoice == 2:
        print('[+] Opening shell... (exit shell command is EXSH)')
        sock = getSock(b'sh\n')
        time.sleep(0.3)
        if not sock:
            continue
        sock.setblocking(0)
        while True:
            command = input('> ')
            if command == 'EXSH':
                sock.close()
                print('[+] Closed the shell')
                break
            sock.send(command.encode() + b'\n')
            time.sleep(0.2)
            while True:
                try:
                    data = sock.recv(4096)
                except:
                    break
                if not data:
                    break
                try:
                    data = data.decode()
                except:
                    pass
                print(data)
    else:
        exit(0)