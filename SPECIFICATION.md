# MFS: MicroFileSystem v1.1  
  
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
Any transport that can gurantee integirty, sequentiality and a stream can be used, but TCP is the preferred transport.  
(As extra clarification, the transport should ALWAYS be a byte-stream like TCP is.)  
  
## Operation codes
Decimal ranges between 0 to 30 is reserved for the MFS spec. Implementations are free to implement non-standard operations beyond it.  
Unused operations within the MFS spec range are to be treated as a no-op.  

0: no operation. Self explanatory.  
1: read. Reads data from the path provided by the message, When the server gets this it should send a message to the requester with data being the contents of the file at path.  
2: write. Writes data of the message to the file at path, Response data should contain the bytes written as a unsigned 32-bit integer (much like dsize).  
3: ls. sends the file paths the server has to the client, akin to POSIX ls. During response, the data field contains all the paths the server has, with '\0's between the paths.  
4: error. data field is the error code (codes are listed below). Normally, this shouldn't be sent out on its own (non-response), so more often than not, this will come as 0x84 
    
  
### Error codes  
Error codes are unsigned 16-bit integers, and must be in the data field with dsize=2.  
(The numbers are in decimal.)  
ranges of 0 to 5000 are reserved for MFS spec.  
  
values ranging from 0 to 999 are internal errors:  
  0: Out of memory  
  1: Operation failed unexpectedly.  
  2: Request exceeded internal buffers.  
  
values ranging from 1000 to 1999 are file errors:  
  1000: File not found  
  1001: Illegal data  
  1002: Writing data failed.  
  1003: Reading data failed.  

values ranging from 2000 to 2999 are transport errors:  
  2000: Sycnhronisation failure. (Sent when the server and/or client detects they are de-synchronised)  

values ranging from 3000 to 4999 are client errors:  
  3000: Timed out.  
  3001: Connection refused.  
  3002: Server no longer serving this client. (Can be used whenever an implementation wants to block a client for some reason)  
  
## Responses  
Responses are messages with the operand being ORed with 0x80.  
Response echo back the file they operated on, for example a read operation's response would have the file it read in the path field, and the contents of the file in the data field.  
  
# EXAMPLE  
Lets say a client wants to write "127" into the PWM node of a PWM capable-pin, 6. to achieve this, it would send this message:  
  
-----------------------------------------------------------------------------------------------  
|          Path size (11)        |           Data size (3)       | Operand|    Path     | Data|  
-----------------------------------------------------------------------------------------------  
|00000000000000000000000000001011|0000000000000000000000000000011|00000010|"/gpio/6/pwm"|"127"|  
-----------------------------------------------------------------------------------------------  
  
After the request, The server responds with the bytes written.  
  
---------------------------------------------------------------------------------------------------------------------------  
|          Path size (11)        |           Data size (1)       | Operand|    Path     |              Data               |  
---------------------------------------------------------------------------------------------------------------------------  
|00000000000000000000000000001011|0000000000000000000000000000001|10000010|"/gpio/6/pwm"| 0000000000000000000000000000011 |  
---------------------------------------------------------------------------------------------------------------------------  
