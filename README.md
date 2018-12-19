# MySQL
DBA days
```
This bash script will be helpful in one time archival using trigger and backfilling based on AUTO INC primary key. 
Arguments:
-d : database name
-t : table name
-c : check slave lag (1/0) - default 1
-s : slave ip - "default: ip of app slave where maxscale_user can connect"
-l : primary key lower limit upto which the archival should continue
-n : no create table (1/0) - default 0. needed when killed script in middle and resume  only backfilling
```

```
Usage: bash archive_and_drop.bash -d <database> -t <table_name> -c < check-lag 1/0> -s <slave-ip> -l <primary key limit > -n <no create table 1/0>
```  
Example : bash archive_and_drop.bash -d test -t event_logs -c "1" -s 10.20.30.40 -l 26743099 -n 0

```
Current database: test

mysql> show tables;
+-----------------+
| Tables_in_test  |
+-----------------+
| invent_logs      |
| invent_logs_test |
| testing         |
+-----------------+
3 rows in set (0.01 sec)

mysql> select min(id),max(id) from invent_logs;
+----------+----------+
| min(id)  | max(id)  |
+----------+----------+
| 23874359 | 26843099 |
+----------+----------+
1 row in set (0.00 sec)

mysql> ^Z
[3]+  Stopped                 mysql

up2:/home/krishnar# bash archive_and_drop.bash -d test -t invent_logs -c "1" -s 10.20.30.40 -l 26743099 -n 0

### START TIME : 2018-11-04 03:06:26

#### Inputs ####
database : test
table : invent_logs
slave-ip :10.20.30.40

#### Performing checks ####
host:	up2.net
 Able to connect with local host.

 Checking for Foreign keys..
 No foreign keys deteceted on test.invent_logs

 Checking for trigger table on test..
 Checking for triggers..
 No triggers present on the test.invent_logs

 #### Triggers created on test.invent_logs ####
invent_logs_insert
invent_logs_update
invent_logs_delete

 #### Backfilling test ####

 starting backfill on invent_logs_triggered ..

 Min id from test.invent_logs before actvity
23874359
Ids not moving on main table, inserting first row on triggered table
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26842098 and 26843098;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26840097 and 26842097;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26837096 and 26840096;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26833095 and 26837095;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26828094 and 26833094;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26822093 and 26828093;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26815092 and 26822092;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26807091 and 26815091;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26798090 and 26807090;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26788089 and 26798089;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26777088 and 26788088;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26765087 and 26777087;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26752086 and 26765086;
 Inserting : insert into invent_logs_triggered select * from invent_logs where id between 26738085 and 26752085;
backfilling done, proceed to rename and drop old table
#### Renaming table ####
rename table test.invent_logs to test.invent_logs_2018Nov04,invent_logs_triggered to test.invent_logs;

 Min id from test.invent_logs after activity:
26738085
 Renaming done successfully, plan to drop table test.invent_logs_2018Nov04
### Mailing details
### END TIME : 2018-11-04 03:07:58
####
```
