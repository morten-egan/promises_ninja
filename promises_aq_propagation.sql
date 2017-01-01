begin
  dbms_aqadm.schedule_propagation (
      queue_name            =>    'promise_async_queue'
      , destination_queue   =>    'promise_job_queue'
      , start_time          =>    sysdate
      , duration            =>    null
      , latency             =>    0
  );
end;
/
