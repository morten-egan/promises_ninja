-- Create the result type.
create or replace type promise_result as object (
  promise_name        varchar2(30)
  , promise_result    varchar2(30)
  , promise_typeval   number
  , promise_value     sys.anydata
  , thenable_status   varchar2(30)
  , thenable_order    number
  , thenable          varchar2(4000)
);
/
