begin
  -- Create the queue table.
  dbms_aqadm.create_queue_table (
    queue_table           =>    'promise_job_tab'
    , queue_payload_type  =>    'promise_result'
    , multiple_consumers  =>    true
    , comment             =>    'queue to support plsql implementation of javascript promises.'
  );

  dbms_aqadm.create_queue (
    queue_name            =>    'promise_job_queue'
    , queue_table         =>    'promise_job_tab'
  );

  dbms_aqadm.start_queue (
    queue_name            =>    'promise_job_queue'
  );

end;
/

begin
  dbms_aqadm.add_subscriber(
    queue_name            =>    'promise_job_queue'
    , subscriber          =>    sys.aq$_agent(
                                  'JOBSUBT'
                                  , null
                                  , null
                                )
  );
end;
/
