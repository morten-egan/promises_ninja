begin
  -- Create the queue table.
  dbms_aqadm.create_queue_table (
    queue_table           =>    'promise_async_tab'
    , queue_payload_type  =>    'promise_result'
    , multiple_consumers  =>    true
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

begin
  dbms_aqadm.add_subscriber(
    queue_name            =>    'promise_async_queue'
    , subscriber          =>    sys.aq$_agent(
                                  'RESULTSUB'
                                  , null
                                  , null
                                )
  );
end;
/

begin
  dbms_aqadm.add_subscriber(
    queue_name            =>    'promise_async_queue'
    , subscriber          =>    sys.aq$_agent(
                                  'JOBSUBS'
                                  , 'promise_job_queue'
                                  , 0
                                )
    , queue_to_queue      =>    true
  );
end;
/
