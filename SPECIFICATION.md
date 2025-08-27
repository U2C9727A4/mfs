# MFS: MicroFileSystem v1  
  
MFS is a lightweight network filesystem protocol designed for MCUs to expose their hardware (or operations) as files over the networks.  
However, MFS is not retricted to MCUs. It should be able to run on any hardware and any OS, as portability is a goal.  
  
# Protocol Specification  
  
MFS operates in 2 diffirent modes, `setup`, and `normal`. They will be explained soon, but first the messages that MFS uses.  
  
psize[4], dsize[4], op[1] path[s], data[s]  
  
in MFS, all integers are little endian.  
psize is an unsigned 32-bit integer that contains the size of the path.  
dsize is an unsigned 32-bit integer that contains the size of the data.  
op is a unsigned 8-bit integer that specificies the operation.  
path is an absolute path (not relative!) to the file that is going to be operated on. (Path seperator is "/"). ASCII encoding.  
data is the data that will be used with the operation.  
  
## Transport  
MFS uses TCP as its transport protocol, for data gurantees.  
Any transport that can provide data integrity and data order gurantees can be used, but TCP is the preferred transport.  
  
## Operation codes  
0: no operation. Self explanatory.  
1: read. Reads data from the path provided by the message, When the server gets this it should send a message to the requester with data being the contents of the file at path.  
2: write. Writes data of the message to the file at path, Response data should contain the bytes written as a unsigned 32-bit integer (much like dsize).  
3: ls. sends the file paths the server has to the client, akin to POSIX ls. During response, the data field contains all the paths the server has, with newlines between the paths. Path is empty!  
  
4: setup. this is a special operation only allowed in the SETUP mode. When the server recieves this in SETUP mode, It should set up it WiFi.  
   The path is treated as the SSID of the WiFi, and data is the password of it, after this is recieved, MFS exits setup mode.  
     
  
### Response Operation Codes  
Response operation codes are simply the operation ORed with `1000000`.  
the write operation in binary form is `00000010`, for the server to send a response of a write operation, it would send `10000010` as the operation.  
  
5: error. data field is the error code (codes are listed below). This can only be sent by the server, and not the client.  
(For clarification, the 5 of the error operation is to be ORed with 10000000, which makes it 10000101 in operation)   
  
### Error codes  
Error codes are unsigned 16-bit integers, and must be in the data field with dsize=2.  
000: File not Found  
001: Operation failed unexpectedly  
  
100: Malformed message  
101: Unknown operation  
102: Illegal operation  
  
010: Timer expired  
  
## Responses  
Responses are messages with the operand being ORed with 10000000.  
Response echo back the file they operated on, for example a read operation's response would have the file it read in the path field, and the contents of the file in the data field.  
  
## Operation modes  
SETUP: SETUP is a special operation mode that allows the device to be set up, using the special setup operation. No other operation is allowed other than setup during this mode.  
  
NORMAL: This is normal operation, where all operations (except setup) are allowed.  
  
# EXAMPLE  
Lets say a client wants to write "127" into the PWM node of a PWM capable-pin, 6. to achieve this, it would send this message:  
  
-----------------------------------------------------------------------------------------------  
|          Path size (11)        |           Data size (3)       | Operand|    Path     | Data|  
-----------------------------------------------------------------------------------------------  
|00000000000000000000000000001011|0000000000000000000000000000011|00000010|"/gpio/6/pwm"|"127"|  
-----------------------------------------------------------------------------------------------  
  
After the request, The server responds with the bytes written.  
  
-----------------------------------------------------------------------------------------------  
|          Path size (11)        |           Data size (1)       | Operand|    Path     | Data|  
-----------------------------------------------------------------------------------------------  
|00000000000000000000000000001011|0000000000000000000000000000001|10000010|"/gpio/6/pwm"| "3" |  
-----------------------------------------------------------------------------------------------  
