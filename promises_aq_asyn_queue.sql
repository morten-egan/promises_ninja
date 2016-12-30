begin
  -- Create the queue table.
  dbms_aqadm.create_queue_table (
    queue_table           =>    'promise_async_tab'
    , queue_payload_type  =>    'promise_result'
    , comment             =>    'queue to support plsql implementation of javascript promises.'
  );

  dbms_aqadm.create_queue (
    queue_name            =>    'promise_async_queue'
    , queue_table         =>    'promise_async_tab'
  );

  dbms_aqadm.start_queue (
    queue_name            =>    'promise_async_queue'
  );

end;
/
