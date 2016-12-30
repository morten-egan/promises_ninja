begin
  -- Create the queue table.
  dbms_aqadm.create_queue_table (
    queue_table           =>    'promise_result_tab'
    , queue_payload_type  =>    'promise_result'
    , multiple_consumers  =>    true
    , comment             =>    'queue to support plsql implementation of javascript promises.'
  );

  dbms_aqadm.create_queue (
    queue_name            =>    'promise_result_queue'
    , queue_table         =>    'promise_result_tab'
  );

  /* dbms_aqadm.add_subscriber (
    queue_name            =>    'promise_result_queue'
    , subscriber          =>    sys.aq$_agent('promise_result_agent', null, null)
  ); */

  dbms_aqadm.start_queue (
    queue_name            =>    'promise_result_queue'
  );

end;
/
