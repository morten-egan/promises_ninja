create user promises_ninja identified by promises_ninja
default tablespace users
temporary tablespace temp;

alter user promises_ninja quota unlimited on users;

grant create session to promises_ninja;
grant create table to promises_ninja;
grant create sequence to promises_ninja;
grant create type to promises_ninja;
grant aq_administrator_role to promises_ninja;
grant create job to promises_ninja;
grant execute on dbms_aqadm to promises_ninja;
grant execute on dbms_aq to promises_ninja;
grant create procedure to promises_ninja;
