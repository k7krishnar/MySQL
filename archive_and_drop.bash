
#!/bin/bash
#Usage: sh $0 -d <database> -t <table_name> -c < check-lag 1/0> -s <slave-ip> -l <primary key limit > -n <no create table 1/0>\n "

dir=$(pwd)
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec > >(tee $dir/log_archive.log) 2>$dir/log_archive.err
trap 'exit 130' INT
set -x
echo -e "### START TIME : $(date "+%F %T")"

shifu()
{
echo -e "### END TIME : $(date "+%F %T")"
alertid="<mailid>"
cat $dir/log_archive.log | mail -s "Archival on $(hostname)" $alertid
exit
}

backfill()
{
interval=1001

table_check1=$(mysql -sNe "SELECT IF( EXISTS(select TABLE_NAME from information_schema.TABLES where TABLE_NAME='$triggered_t' and TABLE_SCHEMA='$db' ),1,0);")
if [ "$table_check1" -eq "0" ];
then
echo " DB/Table combination not existing for $db.$triggered_t .. exiting" && shifu
fi

pri_col=$(mysql -Ne "select COALESCE((select COLUMN_NAME from information_schema.COLUMNS where table_schema='$db' and table_name='$main_t' and COLUMN_KEY='PRI' and EXTRA='auto_increment'),NULL);")
if [ "$pri_col" = "NULL" ];
then
echo "Auto Inc PRIMARY column doen't exist and exiting" && shifu
fi

echo -e " \n Min $pri_col from $db.$main_t before actvity"
mysql $db -sNe "select min($pri_col) from $main_t "
l=$(mysql $db -sNe "select COALESCE((select max($pri_col) from $main_t ),NULL);")
sleep 5
l1=$(mysql $db -sNe "select COALESCE((select max($pri_col) from $main_t ),NULL);")
l2=$(mysql $db -sNe "select COALESCE((select max($pri_col) from $triggered_t ),NULL);")
if [ "$l" -eq "$l1" ] && [ "$l" != "NULL" ] && [ "$l2" = "NULL" ];
then
echo "Ids not moving on main table, inserting first row on triggered table"
mysql -sNe "insert into $db.$triggered_t select * from $db.$main_t where $pri_col=$l"
elif [ "$l" = "NULL" ];
then
echo " NULL returning on max(pri_column) on main table and exiting" && shifu
fi

# to check the slave lag and set the sleep as per it
slave_user="<ReplUser>"
slave_pass="<ReplPass>"
slave_check()
{

# ignore lag-check if mentioned
{
if [ $lag_check -eq 1 ];
then
lag=$(mysql -h$slave_ip -u$slave_user -p$slave_pass -se "show slave status \G" | grep Seconds_Behind_Master | cut -d':' -f2)
else
lag=0
fi
}

if [ $lag -ge 3 ] ;
then
sleep $lag
interval=$((interval-1000))
slave_check
if [ $interval -lt 100 ]; then interval=100 ; fi
else
interval=$((interval+1000))
if [ $interval -gt 30000 ]; then interval=30000 ; fi
sleep 0.3
fi
}

{
# configure the minimum id until the backfill should happen (eg. min(id) where now() -7 days )

minid=$(mysql $db -sNe "select min($pri_col) from $triggered_t")

until [ $minid -le $stop ]
do
curid=$(mysql $db -sNe "select min($pri_col) from $triggered_t")
minid=$(mysql $db -sNe "select max($pri_col) from $main_t where $pri_col < $curid")
min=$(($minid-$interval))
if [ $min -lt $stop ]
then
min=$stop
fi
max=$(($minid))
slave_check
if [ $min -gt 0 ] || [ $max -gt 0 ];
then
echo " Inserting : insert into $triggered_t select * from $main_t where $pri_col between $min and $max;" 
mysql $db -sNe "insert into $triggered_t select * from $main_t where $pri_col between $min and $max;"
else
echo " Ids are in negative; exiting" && shifu
fi
minid=$(mysql $db -sNe "select min($pri_col) from $triggered_t")

# uncomment to exit on first execution of loop
#exit
done

echo "backfilling done, proceed to rename and drop old table"
echo "#### Renaming table ####"
{
old_t=$(echo "$main_t"_$(date "+%Y%b%d"))
last_id=$(mysql $db -sNe "select min($pri_col) from $main_t")
echo "rename table $db.$main_t to $db.$old_t,$triggered_t to $db.$main_t;"

timeout 180 mysql $db -sNe "rename table $db.$main_t to $db.$old_t,$triggered_t to $db.$main_t"
last_id1=$(mysql $db -sNe "select min($pri_col) from $old_t")

echo -e " \n Min $pri_col from $db.$main_t after activity:"
mysql $db -sNe "select min($pri_col) from $main_t"


if [ "$last_id1" -eq "$last_id" ] && [ "$last_id1" -gt "1" ];
then
echo " Renaming done successfully, plan to drop table $db.$old_t"
fi
}
}
}

# generate triggers
create_trigger()
{

echo -e " Checking for Foreign keys.."

table_check=$(mysql -sNe "SELECT IF( EXISTS(select TABLE_NAME from information_schema.TABLES where TABLE_NAME='$main_t' and TABLE_SCHEMA='$db'),1,0);")
if [ "$table_check" -eq "0" ];
then
echo " DB/Table combination not existing for $db.$main_t .. exiting" && shifu
else
{
fk=$(mysql -sNe "SELECT IF( EXISTS(select CONSTRAINT_NAME from information_schema.REFERENTIAL_CONSTRAINTS where TABLE_NAME='$main_t' or REFERENCED_TABLE_NAME='$main_t' and CONSTRAINT_SCHEMA='$db'),1,0);")
if [ "$fk" -eq "0" ];
then
{
echo -e " No foreign keys deteceted on $db.$main_t \n"

{
echo " Checking for trigger table on $db.."
table_check1=$(mysql -sNe "SELECT IF( EXISTS(select TABLE_NAME from information_schema.TABLES where TABLE_NAME='$triggered_t' and TABLE_SCHEMA='$db'),1,0);")
if [ "$table_check1" -eq "1" ];
then
echo " Trigger table $triggered_t already existing on $db.. exiting" && shifu
fi
}

{
echo -e " Checking for triggers.."
ins_trig=$(echo "$main_t"_insert)
upd_trig=$(echo "$main_t"_update)
del_trig=$(echo "$main_t"_delete)

trig=$(mysql -sNe "SELECT IF( EXISTS(select TRIGGER_NAME from information_schema.TRIGGERS where TRIGGER_SCHEMA='$db' and TRIGGER_NAME in ('$ins_trig','$upd_trig','$del_trig')),1,0);")
if [ "$trig" -eq "0" ];
then
echo -e " No triggers present on the $db.$main_t"

pri_col=$(mysql -Ne "select COALESCE((select COLUMN_NAME from information_schema.COLUMNS where table_schema='$db' and table_name='$main_t' and COLUMN_KEY='PRI' and EXTRA='auto_increment'),NULL);")
if [ "$pri_col" = "NULL" ];
then
echo "Auto Inc PRIMARY column doen't exist and exiting" && shifu
fi

    {
mysql -sN << EOF >trigger_query.sql
set group_concat_max_len=555555;

set @db='$db';
set @tbl='$main_t';
set @tbl_new='$triggered_t';
set @col=(select group_concat(column_name) from information_schema.columns where table_name=@tbl and table_schema=@db order by ORDINAL_POSITION);
set @newcol=(select group_concat('New.',column_name) from information_schema.columns where table_name=@tbl and table_schema=@db order by ORDINAL_POSITION);
set @upcol=(select group_concat(column_name,'=New.',column_name) from information_schema.columns where table_name=@tbl and table_schema=@db order by ORDINAL_POSITION);

select concat('use ',@db,';');
select concat('create table ',@tbl_new,' like ',@tbl ,';');

select '#insert_trigger';
select 'delimiter //';
select group_concat('create trigger ',@tbl,'_insert after insert on ',@db,'.',@tbl,' FOR EACH ROW BEGIN insert into ',@db,'.',@tbl_new,'(',@col,') values (',@newcol,');');
select 'END//';
select 'delimiter ;';

select '#update_trigger';
select 'delimiter //';
select group_concat('create trigger ',@tbl,'_update after update on ',@db,'.',@tbl,' FOR EACH ROW BEGIN update ',@db,'.',@tbl_new,' set ',@upcol,' where $pri_col=new.$pri_col;');
select 'END//';
select 'delimiter ;';

select 'delimiter //';
select '#delete_trigger';
select group_concat('create trigger ',@tbl,'_delete after delete on ',@db,'.',@tbl,' FOR EACH ROW BEGIN delete ignore from ',@db,'.',@tbl_new,' where $pri_col=old.$pri_col;');
select 'END//';
select 'delimiter ;';
EOF

# create triggers
mysql -sN < trigger_query.sql

if [ $? -eq 0 ];
then
echo -e "\n #### Triggers created on $db.$main_t ####"
mysql -Ne "select TRIGGER_NAME from information_schema.TRIGGERS where TRIGGER_SCHEMA='$db' and EVENT_OBJECT_TABLE='$main_t'"
echo -e "\n #### Backfilling $db ####"
echo -e "\n starting backfill on $triggered_t .."
backfill
else
echo "Error during creating triggers"
fi

    }
else
echo -e " Triggers already present on the $db.$main_t , exiting " && shifu
fi
}
}
else
echo -e " Foreign_key constraint exists for the table. if child table, create new fk and trigger table manually and proceed" && shifu
fi
}
fi
}

prechecks()
{
timeout 3 mysql -sNe 'select "host:",@@hostname'
if [ "$?" -eq "0" ];
then
echo -e " Able to connect with local host.\n"
create_trigger
else
echo -e " Not able to connect to mysql, exiting" && shifu
fi
}


while getopts "d:t:c:s:l:n:" opt; do
  case ${opt} in
    d ) db=$OPTARG ;;
    t ) main_t=$OPTARG ;;
    c ) lag_check=$OPTARG ;;
    s ) slave_ip=$OPTARG ;;
    l ) stop=$OPTARG ;;
    n ) no_create=$OPTARG ;;
  esac
done

if [ $# -lt 12 ] ; then
    echo -e "\n Insufficent arguments \n Usage: sh $0 -d <database> -t <table_name> -c < check-lag 1/0> -s <slave-ip> -l <primary key limit > -n <no create table 1/0>\n "

else
triggered_t=$(echo "$main_t"_triggered)

echo -e "\n#### Inputs ####"
echo -e database : $db
echo -e table : $main_t
echo -e slave-ip :$slave_ip
echo -e "\n#### Performing checks ####"

if [ "$no_create" -eq "0" ];
then
prechecks
else
backfill
fi
fi
# end of script
echo -e "### Mailing details"
shifu
