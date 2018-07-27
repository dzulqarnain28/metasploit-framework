# iec104
IEC104 Client for Metasploit

## Install
Create a new folder for the IEC104 module, place script in new folder 

```
mkdir -p $HOME/.msf4/modules/auxiliary/client/iec104
cp iec104.rb $HOME/.msf4/modules/auxiliary/client/iec104/
```

## Usage
### Selection of module in msfconsole
```
msf > use auxiliary/client/iec104/iec104
```

### Show module options
```
msf auxiliary(client/iec104/iec104) > show options

Module options (auxiliary/client/iec104/iec104):

   Name                Current Setting  Required  Description
   ----                ---------------  --------  -----------
   ASDU_ADDRESS        1                yes       Common Address of ASDU
   COMMAND_ADDRESS     0                yes       Command Address / IOA Address
   COMMAND_TYPE        100              yes       Command Type
   COMMAND_VALUE       20               yes       Command Value
   ORIGINATOR_ADDRESS  0                yes       Originator Address
   RHOST                                yes       The target address
   RPORT               2404             yes       The target port (TCP)


Auxiliary action:

   Name          Description
   ----          -----------
   SEND_COMMAND  Send command to device
```

### Usage Examples
Example of sending IEC104 general interrogation command
This is using thde default setting for command type, address and value, this is connecting to an local IEC104 server simulator for demo purposes
```
msf auxiliary(client/iec104/iec104) > set rhost 127.0.0.1
rhost => 127.0.0.1
msf auxiliary(client/iec104/iec104) > run

[+] 127.0.0.1:2404 - Recieved STARTDT_ACT
[*] 127.0.0.1:2404 - Sending 104 command
[+] 127.0.0.1:2404 -   Parsing response: Interrogation command (C_IC_NA_1)
[+] 127.0.0.1:2404 -     TX: 0002 RX: 0000
[+] 127.0.0.1:2404 -     CauseTx: 07 (Activation Confirmation)
[+] 127.0.0.1:2404 -   Parsing response: Single point information (M_SP_NA_1)
[+] 127.0.0.1:2404 -     TX: 0002 RX: 0002
[+] 127.0.0.1:2404 -     CauseTx: 14 (Inrogen)
[+] 127.0.0.1:2404 -     IOA: 1 SIQ: 0x00
[+] 127.0.0.1:2404 -     IOA: 2 SIQ: 0x00
[+] 127.0.0.1:2404 -     IOA: 3 SIQ: 0x01
[+] 127.0.0.1:2404 -     IOA: 4 SIQ: 0x00
[+] 127.0.0.1:2404 -   Parsing response: Single point information (M_SP_NA_1)
[+] 127.0.0.1:2404 -     TX: 0002 RX: 0004
[+] 127.0.0.1:2404 -     CauseTx: 14 (Inrogen)
[+] 127.0.0.1:2404 -     IOA: 7 SIQ: 0x00
[+] 127.0.0.1:2404 -   Parsing response: Double point information (M_DP_NA_1)
[+] 127.0.0.1:2404 -     TX: 0002 RX: 0006
[+] 127.0.0.1:2404 -     CauseTx: 14 (Inrogen)
[+] 127.0.0.1:2404 -     IOA: 6 SIQ: 0x02
[+] 127.0.0.1:2404 -   Parsing response: Interrogation command (C_IC_NA_1)
[+] 127.0.0.1:2404 -     TX: 0002 RX: 0008
[+] 127.0.0.1:2404 -     CauseTx: 0a (Termination Activation)
[*] 127.0.0.1:2404 - operation ended
[*] 127.0.0.1:2404 - Terminating Connection
[+] 127.0.0.1:2404 - Recieved STOPDT_ACT
[*] Auxiliary module execution completed
msf auxiliary(client/iec104/iec104) >
```

Example sending switching command
IOA address to be switched is "5", the command type is a double command "46", command is for switching off without time value "5"
Using local IEC 104 server simulator

```
msf auxiliary(client/iec104/iec104) > set rhost 127.0.0.1
rhost => 127.0.0.1
msf auxiliary(client/iec104/iec104) > set command_address 5
command_address => 5
msf auxiliary(client/iec104/iec104) > set command_type 46
command_type => 46
msf auxiliary(client/iec104/iec104) > set command_value 5
command_value => 5
msf auxiliary(client/iec104/iec104) > run

[+] 127.0.0.1:2404 - Recieved STARTDT_ACT
[*] 127.0.0.1:2404 - Sending 104 command
[+] 127.0.0.1:2404 -   Parsing response: Double command (C_DC_NA_1)
[+] 127.0.0.1:2404 -     TX: 0002 RX: 0000
[+] 127.0.0.1:2404 -     CauseTx: 07 (Activation Confirmation)
[+] 127.0.0.1:2404 -     IOA: 5 DCO: 0x05
[+] 127.0.0.1:2404 -   Parsing response: Single point information with time (M_SP_TB_1)
[+] 127.0.0.1:2404 -     TX: 0002 RX: 0002
[+] 127.0.0.1:2404 -     CauseTx: 03 (Spontaneous)
[+] 127.0.0.1:2404 -     IOA: 3 SIQ: 0x00
[+] 127.0.0.1:2404 -     Timestamp: 2018-03-30 21:39:52.930
[+] 127.0.0.1:2404 -   Parsing response: Double command (C_DC_NA_1)
[+] 127.0.0.1:2404 -     TX: 0002 RX: 0004
[+] 127.0.0.1:2404 -     CauseTx: 0a (Termination Activation)
[+] 127.0.0.1:2404 -     IOA: 5 DCO: 0x05
[*] 127.0.0.1:2404 - operation ended
[*] 127.0.0.1:2404 - Terminating Connection
[+] 127.0.0.1:2404 - Recieved STOPDT_ACT
[*] Auxiliary module execution completed
msf auxiliary(client/iec104/iec104) >
```
