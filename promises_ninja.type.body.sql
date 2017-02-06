create or replace type body promise as

  constructor function promise
  return self as result

  as

  begin

    self.promise_name := self.get_promise_name();
    self.state := 'pending';
    self.typeval := 0;
    self.o_executor := null;
    self.o_execute := 0;
    self.chain_size := 0;

    return;

  end promise;

  constructor function promise (
    executor            varchar2
  )
  return self as result

  as

  begin

    self.promise_name := self.get_promise_name();
    self.state := 'pending';
    self.typeval := 0;
    self.o_executor := executor;
    self.o_executor_typeval := 0;
    self.o_execute := 0;
    self.chain_size := 0;

    self.validate_p();

    self.execute_promise();

    return;

  end promise;

  constructor function promise (
    executor            varchar2
    , executor_val      number
  )
  return self as result

  as

  begin

    self.promise_name := self.get_promise_name();
    self.state := 'pending';
    self.typeval := 0;
    self.o_executor := executor;
    self.o_executor_typeval := 1;
    self.o_executor_val := sys.anydata.convertnumber(executor_val);
    self.o_execute := 0;
    self.chain_size := 0;

    self.validate_p();

    self.execute_promise();

    return;

  end promise;

  constructor function promise (
    executor            varchar2
    , executor_val      varchar2
  )
  return self as result

  as

  begin

    self.promise_name := self.get_promise_name();
    self.state := 'pending';
    self.typeval := 0;
    self.o_executor := executor;
    self.o_executor_typeval := 2;
    self.o_executor_val := sys.anydata.convertvarchar2(executor_val);
    self.o_execute := 0;
    self.chain_size := 0;

    self.validate_p();

    self.execute_promise();

    return;

  end promise;

  constructor function promise (
    executor            varchar2
    , executor_val      date
  )
  return self as result

  as

  begin

    self.promise_name := self.get_promise_name();
    self.state := 'pending';
    self.typeval := 0;
    self.o_executor := executor;
    self.o_executor_typeval := 4;
    self.o_executor_val := sys.anydata.convertdate(executor_val);
    self.o_execute := 0;
    self.chain_size := 0;

    self.validate_p();

    self.execute_promise();

    return;

  end promise;

  member procedure validate_p (
    self                in out nocopy        promise
  )

  as

    l_function_exists       number;
    l_function_input        all_arguments%rowtype;
    l_function_output       all_arguments%rowtype;

  begin

    if self.o_executor != 'E_PROMISE' then
      -- We have a normal function as executor. Check that it exists.
      select count(*)
      into l_function_exists
      from all_objects
      where object_name = upper(self.o_executor)
      and object_type = 'FUNCTION';
      if l_function_exists > 0 then
        -- Function exists
        -- Check input type, if called with input val.
        if self.o_executor_typeval > 0 then
          begin
            select *
            into l_function_input
            from all_arguments
            where object_name = upper(self.o_executor)
            and in_out = 'IN'
            and position = 1;
            if l_function_input.data_type = 'NUMBER' and self.o_executor_typeval != 1 then
              raise_application_error(-20042, 'promise executor, input parameter mismatch');
            elsif l_function_input.data_type = 'VARCHAR2' and self.o_executor_typeval != 2 then
              raise_application_error(-20042, 'promise executor, input parameter mismatch');
            elsif l_function_input.data_type = 'DATE' and self.o_executor_typeval != 4 then
              raise_application_error(-20042, 'promise executor, input parameter mismatch');
            end if;
            exception
              when others then
                raise_application_error(-20042, 'promise executor, input parameter mismatch');
          end;
        end if;
        -- Check and set the output type.
        select *
        into l_function_output
        from all_arguments
        where object_name = upper(self.o_executor)
        and in_out = 'OUT';
        if l_function_output.data_type = 'NUMBER' then
          self.typeval := 1;
        elsif l_function_output.data_type = 'VARCHAR2' then
          self.typeval := 2;
        elsif l_function_output.data_type = 'DATE' then
          self.typeval := 4;
        else
          raise_application_error(-20042, 'only number, varchar2 or date output currently supported for promises');
        end if;
      else
        raise_application_error(-20042, 'promise executor invalid privileges or does not exist');
      end if;
    else
      -- We have a promise. Add self to chain with correct dependencies.
      null;
    end if;

    -- We have reached the end of the validation procedure.
    -- Enable execution of promise.
    self.o_execute := 1;

  end validate_p;

  member function get_promise_name
  return varchar2

  as

  begin

    return 'P_' || substr(sys_guid(), 1, 26);

  end get_promise_name;

  member function on_is_function(
    function_name                       varchar2
  ) return boolean

  as

    l_exists_and_is_func        number;

  begin

    select count(*)
    into l_exists_and_is_func
    from all_objects
    where object_name = upper(function_name)
    and object_type = 'FUNCTION';

    if l_exists_and_is_func > 0 then
      return true;
    else
      return false;
    end if;

  end on_is_function;

  member procedure then_p (
    self                    in out      promise
    , ref_promise           in out      promise
    , on_fullfilled                     varchar2    default null
    , on_rejected                       varchar2    default null
  )

  as

  begin

    if self.chain_size = 0 then
      ref_promise := self.then_f(on_fullfilled, on_rejected);
    else
      if ref_promise is null then
        -- Attach equal thenable to original promise (will start independent chain)
        ref_promise := self.then_f(on_fullfilled, on_rejected);
      else
        -- Add to chain of promises.
        ref_promise := ref_promise.then_f(on_fullfilled, on_rejected);
      end if;
    end if;

  end then_p;

  member function catch (
    self                  in out      promise
    , on_rejected                     varchar2
  )
  return promise

  as

  begin

    return self.then_f(null, on_rejected);

  end catch;

  member function then_f (
    self                  in out      promise
    , on_fullfilled                   varchar2      default null
    , on_rejected                     varchar2      default null
  )
  return promise

  as

    new_promise                 promise;
    l_anonymous_plsql_block     varchar2(32000);
    l_thenable_result           promise_result;

  begin


    -- First check if promise has been validated.
    -- Do not allow to thenable a promise that has not been validated to be executed.
    if self.o_execute > 0 then
      -- Initiate the new promise that we will return.
      new_promise := promise();

      -- Poll for the answer and set if available.
      self.check_and_set_value;

      self.chain_size := self.chain_size + 1;

      if self.state = 'fulfilled' then
        -- We already have the final result of the promise.
        -- Add new job directly, with promise value only if on_fulfilled is a real function.
        if on_fullfilled is not null then
          if self.on_is_function(on_fullfilled) then
            case self.typeval
              when 1 then new_promise := promise(on_fullfilled, sys.anydata.accessNumber(self.val));
              when 2 then new_promise := promise(on_fullfilled, sys.anydata.accessVarchar2(self.val));
              when 4 then new_promise := promise(on_fullfilled, sys.anydata.accessDate(self.val));
            end case;
          else
            -- on_fulfilled is not a function. Standard says ignore.
            -- Save space for future changes to on_fulfilled handling.
            null;
          end if;
        end if;
      elsif self.state = 'rejected' then
        -- Check if on_rejected is set.
        if on_rejected is not null then
          if self.on_is_function(on_rejected) then
            case self.typeval
              when 1 then new_promise := promise(on_rejected, sys.anydata.accessNumber(self.val));
              when 2 then new_promise := promise(on_rejected, sys.anydata.accessVarchar2(self.val));
              when 4 then new_promise := promise(on_rejected, sys.anydata.accessDate(self.val));
            end case;
          else
            -- on_rejected is not a function. Ignore for now
            -- save space for future handling.
            null;
          end if;
        end if;
      else
        -- We are in pending and so the "on" triggers will have to poll for results.
        -- Here we should setup a job for either on_fulfilled, on_rejected or both.
        -- (One physical job, with a compounded block to handle all).
        l_anonymous_plsql_block := self.get_then_job_code(on_fullfilled, on_rejected, new_promise.promise_name);
        -- TODO this is where we should put the new promise as a promise result in the asynch queue but with status pending
        -- TODO and the thenable code in the promise result object, along with the order and thenable status.
        -- TODO Lookup promise result valtype here and set correctly in new_promise.
        l_thenable_result := promise_result(new_promise.promise_name, 'pending', 1, null, self.promise_name, self.chain_size, l_anonymous_plsql_block);
        self.result_enqueue('promise_async_queue', l_thenable_result);
        -- When we have built the anonymous plsql and enqueued the message
        -- we have also automatically validated the new promise. Set to validated.
        new_promise.o_execute := 1;
      end if;

      new_promise.typeval := get_function_return(on_fullfilled);
      return new_promise;
    else
      raise_application_error(-20042, 'cannot call then on promise that is not validated');
    end if;

  end then_f;

  member procedure execute_promise(
    self in out nocopy promise
  )

  as

    l_anonymous_plsql_block       varchar2(32000);

  begin

    if self.o_execute > 0 then
      l_anonymous_plsql_block := self.get_exec_job_code;

      dbms_scheduler.create_job(
        job_name            =>    self.promise_name || '_J'
        , job_type          =>    'PLSQL_BLOCK'
        , job_action        =>    l_anonymous_plsql_block
        , enabled           =>    true
      );
    else
      raise_application_error(-20042, 'cannot execute unvalidated promise');
    end if;

  end execute_promise;

  member procedure check_and_set_value(self in out promise)

  as

    l_promise_result      promise_result;
    l_dequeue_options     dbms_aq.dequeue_options_t;
    l_message_properties  dbms_aq.message_properties_t;
    l_first_dequeue       boolean := true;
    l_message_handle      raw(16);

    -- Exceptions
    l_exception_timeout   exception;
    pragma exception_init(l_exception_timeout, -25228);

  begin

      if self.state = 'pending' then

        loop
          -- non-destructive dequeue
          l_dequeue_options.dequeue_mode := dbms_aq.browse;
          l_dequeue_options.wait := dbms_aq.no_wait;
          l_dequeue_options.visibility := dbms_aq.immediate;
          if l_first_dequeue then
            l_dequeue_options.navigation := dbms_aq.first_message;
          else
            l_dequeue_options.navigation := dbms_aq.next_message;
          end if;

          -- dequeue
          dbms_aq.dequeue(
            queue_name              =>    'promise_async_queue'
            , dequeue_options       =>    l_dequeue_options
            , message_properties    =>    l_message_properties
            , payload               =>    l_promise_result
            , msgid                 =>    l_message_handle
          );

          if l_first_dequeue then
            l_first_dequeue := false;
          end if;

          if l_promise_result.promise_name = self.promise_name then
            -- Set value or rejection. We have the result.
            if l_promise_result.promise_result = 'SUCCESS' then
              -- Set state to fulfilled and set the result value.
              -- self.set_state('fulfilled', l_promise_result.promise_value);
              self.state := 'fulfilled';
              self.val := l_promise_result.promise_value;
              self.typeval := l_promise_result.promise_typeval;
            elsif l_promise_result.promise_result = 'FAILURE' then
              -- Set state to rejected and set the rejection result.
              self.state := 'rejected';
              self.val := l_promise_result.promise_value;
              self.typeval := l_promise_result.promise_typeval;
            end if;
          end if;
        end loop;

      end if;

      exception
        when l_exception_timeout then
          null;

  end check_and_set_value;

  member procedure result_enqueue(
    self              in out    promise
    , queue_name                varchar2
    , queue_message             promise_result
  )

  as

    l_enqueue_options     dbms_aq.enqueue_options_t;
    l_message_properties  dbms_aq.message_properties_t;
    l_message_recipients  dbms_aq.aq$_recipient_list_t;
    l_message_handle      raw(16);

  begin

    l_message_properties.expiration := promises_ninja.promise_lifetime;

    dbms_aq.enqueue(
      queue_name            =>    queue_name
      , enqueue_options     =>    l_enqueue_options
      , message_properties  =>    l_message_properties
      , payload             =>    queue_message
      , msgid               =>    l_message_handle
    );
    commit;

  end result_enqueue;

  member procedure job_enqueue(
    self              in out    promise
    , queue_name                varchar2
    , queue_message             promise_job_notify
  )

  as

    l_enqueue_options     dbms_aq.enqueue_options_t;
    l_message_properties  dbms_aq.message_properties_t;
    l_message_recipients  dbms_aq.aq$_recipient_list_t;
    l_message_handle      raw(16);

  begin

    l_message_properties.expiration := promises_ninja.promise_lifetime;

    dbms_aq.enqueue(
      queue_name            =>    queue_name
      , enqueue_options     =>    l_enqueue_options
      , message_properties  =>    l_message_properties
      , payload             =>    queue_message
      , msgid               =>    l_message_handle
    );
    commit;

  end job_enqueue;

  member procedure resolve(
    self              in out    promise
    , resolved_val              promise
  )

  as

  begin

    if self.state = 'pending' then
      if resolved_val.state = 'fulfilled' then
        self.o_execute := 1;
        self.typeval := resolved_val.typeval;
        self.val := resolved_val.val;
        self.state := 'fulfilled';
        self.result_enqueue('promise_async_queue', promise_result(self.promise_name, 'SUCCESS', self.typeval, self.val, null, null, null));
        self.job_enqueue('promise_job_queue', promise_job_notify(self.promise_name, 'SUCCESS'));
      elsif resolved_val.state = 'rejected' then
        raise_application_error(-20042, 'cannot resolve a promise with another rejected promise');
      else
        raise_application_error(-20042, 'resolving by pending promises not supported as of now');
      end if;
    else
      raise_application_error(-20042, 'promises cannot be resolved if already resolved or rejected');
    end if;

  end resolve;

  member procedure resolve(
    self              in out    promise
    , resolved_val              number
  )

  as

  begin

    if self.state = 'pending' then
      self.o_execute := 1;
      self.state := 'fulfilled';
      self.typeval := 1;
      self.val := sys.anydata.convertnumber(resolved_val);
      self.result_enqueue('promise_async_queue', promise_result(self.promise_name, 'SUCCESS', self.typeval, self.val, null, null, null));
      self.job_enqueue('promise_job_queue', promise_job_notify(self.promise_name, 'SUCCESS'));
    else
      raise_application_error(-20042, 'promises cannot be resolved if already resolved or rejected');
    end if;

  end resolve;

  member procedure resolve(
    self              in out    promise
    , resolved_val              varchar2
  )

  as

  begin

    if self.state = 'pending' then
      self.o_execute := 1;
      self.state := 'fulfilled';
      self.typeval := 2;
      self.val := sys.anydata.convertvarchar2(resolved_val);
      self.result_enqueue('promise_async_queue', promise_result(self.promise_name, 'SUCCESS', self.typeval, self.val, null, null, null));
      self.job_enqueue('promise_job_queue', promise_job_notify(self.promise_name, 'SUCCESS'));
    else
      raise_application_error(-20042, 'promises cannot be resolved if already resolved or rejected');
    end if;

  end resolve;

  member procedure resolve(
    self              in out    promise
    , resolved_val              date
  )

  as

  begin

    if self.state = 'pending' then
      self.o_execute := 1;
      self.state := 'fulfilled';
      self.typeval := 4;
      self.val := sys.anydata.convertdate(resolved_val);
      self.result_enqueue('promise_async_queue', promise_result(self.promise_name, 'SUCCESS', self.typeval, self.val, null, null, null));
      self.job_enqueue('promise_job_queue', promise_job_notify(self.promise_name, 'SUCCESS'));
    else
      raise_application_error(-20042, 'promises cannot be resolved if already resolved or rejected');
    end if;

  end resolve;

  member procedure reject(
    self              in out    promise
    , rejection                 varchar2
  )

  as

  begin

    if self.state = 'pending' then
      self.o_execute := 1;
      self.state := 'rejected';
      self.typeval := 2;
      self.val := sys.anydata.convertvarchar2(rejection);
      self.result_enqueue('promise_async_queue', promise_result(self.promise_name, 'FAILURE', self.typeval, self.val, null, null, null));
      self.job_enqueue('promise_job_queue', promise_job_notify(self.promise_name, 'FAILURE'));
    else
      raise_application_error(-20042, 'promises cannot be rejected if already resolved or rejected');
    end if;

  end reject;

  member function getvalue(self in out promise)
  return sys.anydata

  as

  begin

    self.check_and_set_value;

    if self.state = 'pending' then
      return sys.anydata.convertvarchar2(null);
    elsif self.state in ('rejected', 'fulfilled') then
      -- We can return the value. We will never change once we are in this state.
      return self.val;
    else
      -- Dont know what happened here.
      raise_application_error(-20042, 'promise in invalid state: ' || self.state);
    end if;

  end getvalue;

  member function getvalue_number(self in out promise)
  return number

  as

    l_ret_val         number;

  begin

    self.check_and_set_value;

    if self.typeval = 1 then
      if self.state = 'pending' then
        l_ret_val := null;
      else
        l_ret_val := sys.anydata.accessNumber(self.val);
      end if;
      return l_ret_val;
    else
      raise_application_error(-20042, 'promise value not a number');
    end if;

  end getvalue_number;

  member function getvalue_varchar(self in out promise)
  return varchar2

  as

    l_ret_val       varchar2(32000);

  begin

    self.check_and_set_value;

    if self.typeval = 2 then
      if self.state = 'pending' then
        l_ret_val := null;
      else
        l_ret_val := sys.anydata.accessVarchar2(self.val);
      end if;
      return l_ret_val;
    else
      raise_application_error(-20042, 'promise value not a varchar2');
    end if;

  end getvalue_varchar;

  member function getvalue_date(self in out promise)
  return date

  as

    l_ret_val       date;

  begin

    self.check_and_set_value;

    if self.typeval = 4 then
      if self.state = 'pending' then
        l_ret_val := null;
      else
        l_ret_val := sys.anydata.accessDate(self.val);
      end if;
      return l_ret_val;
    else
      raise_application_error(-20042, 'promise value not a date');
    end if;

  end getvalue_date;

  member function getanyvalue(self in out promise)
  return varchar2

  as

    l_ret_val           varchar2(4000);
    l_num               number;
    l_date              date;
    l_extracted_val     sys.anydata;

  begin

    self.check_and_set_value;

    if self.state = 'pending' then
      l_ret_val := null;
    else
      l_extracted_val := self.val;
      case l_extracted_val.gettypename
        when 'SYS.NUMBER' then
          if (l_extracted_val.getNumber(l_num) = dbms_types.success ) then l_ret_val := l_num; end if;
        when 'SYS.DATE' then
          if (l_extracted_val.getDate(l_date) = dbms_types.success ) then l_ret_val := l_date; end if;
        when 'SYS.VARCHAR2' then
          if (l_extracted_val.getVarchar2(l_ret_val) = dbms_types.success ) then null; end if;
        else
          l_ret_val := '** unknown value type **';
      end case;
    end if;

    return l_ret_val;

  end getanyvalue;

  member function get_exec_job_code
  return varchar2

  as

    l_anonymous_plsql_block       varchar2(32000);

  begin

    l_anonymous_plsql_block := 'declare
      l_fe varchar2(4000);
      l_eo dbms_aq.enqueue_options_t;
      l_mp dbms_aq.message_properties_t;
      l_mh raw(16);
      l_qm promise_result;
      l_jm promise_job_notify;
      l_pr ';
    if self.typeval = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'number;';
    elsif self.typeval = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    elsif self.typeval = 4 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'date;';
    end if;
    if self.o_executor_typeval > 0 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '
      l_ev ';
      if self.o_executor_typeval = 1 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'number := ' || to_char(sys.anydata.accessNumber(self.o_executor_val)) || ';';
      elsif self.o_executor_typeval = 2 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000) := ''' || to_char(sys.anydata.accessVarchar2(self.o_executor_val)) || ''';';
      elsif self.o_executor_typeval = 4 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'date := to_date(''' || to_char(sys.anydata.accessDate(self.o_executor_val)) || ''');';
      end if;
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
      begin
        l_pr := ';
    if self.o_executor_typeval > 0 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || self.o_executor || '(l_ev);';
    else
      l_anonymous_plsql_block := l_anonymous_plsql_block || self.o_executor || ';';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
        l_qm := promise_result';
    if self.typeval = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '(''' || self.promise_name || ''', ''SUCCESS'', 1, sys.anydata.convertnumber(l_pr), null, null, null);';
    elsif self.typeval = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '(''' || self.promise_name || ''', ''SUCCESS'', 2, sys.anydata.convertvarchar2(l_pr), null, null, null);';
    elsif self.typeval = 4 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '(''' || self.promise_name || ''', ''SUCCESS'', 4, sys.anydata.convertdate(l_pr), null, null, null);';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
        l_jm := promise_job_notify(''' || self.promise_name || ''', ''SUCCESS'');
        dbms_aq.enqueue(
          queue_name => ''promise_async_queue''
          , enqueue_options => l_eo
          , message_properties => l_mp
          , payload => l_qm
          , msgid => l_mh
        );
        dbms_aq.enqueue(
          queue_name => ''promise_job_queue''
          , enqueue_options => l_eo
          , message_properties => l_mp
          , payload => l_jm
          , msgid => l_mh
        );
        commit;
        exception
          when others then
            l_fe := SQLCODE || ''-'' || SQLERRM;
            l_qm := promise_result(''' || self.promise_name || ''', ''FAILURE'', 2, sys.anydata.convertvarchar2(l_fe), null, null, null);
            l_jm := promise_job_notify(''' || self.promise_name || ''', ''FAILURE'');
            dbms_aq.enqueue(
              queue_name => ''promise_async_queue''
              , enqueue_options => l_eo
              , message_properties => l_mp
              , payload => l_qm
              , msgid => l_mh
            );
            dbms_aq.enqueue(
              queue_name => ''promise_job_queue''
              , enqueue_options => l_eo
              , message_properties => l_mp
              , payload => l_jm
              , msgid => l_mh
            );
            commit;
      end;';

      return l_anonymous_plsql_block;

  end get_exec_job_code;

  member function get_then_job_code(
    on_fullfilled           varchar2
    , on_rejected           varchar2
    , new_promise_name      varchar2
  )
  return varchar2

  as

    l_anonymous_plsql_block       varchar2(32000);
    l_function_output             all_arguments%rowtype;
    l_on_fullfilled_output_type   number;
    l_on_rejected_output_type     number;
    l_fulfilled_input_count       number;
    l_rejected_input_count        number;

  begin

    -- Check and set the output type for each.
    if on_fullfilled is not null then
      select *
      into l_function_output
      from all_arguments
      where object_name = upper(on_fullfilled)
      and in_out = 'OUT';
      if l_function_output.data_type = 'NUMBER' then
        l_on_fullfilled_output_type := 1;
      elsif l_function_output.data_type = 'VARCHAR2' then
        l_on_fullfilled_output_type := 2;
      elsif l_function_output.data_type = 'DATE' then
        l_on_fullfilled_output_type := 4;
      else
        raise_application_error(-20042, 'unsupported output type (on_fulfilled) inside then call');
      end if;
      -- Check if need input at all.
      select count(*)
      into l_fulfilled_input_count
      from all_arguments
      where object_name = upper(on_fullfilled)
      and in_out = 'IN';
    end if;

    if on_rejected is not null then
      select *
      into l_function_output
      from all_arguments
      where object_name = upper(on_rejected)
      and in_out = 'OUT';
      if l_function_output.data_type = 'NUMBER' then
        l_on_rejected_output_type := 1;
      elsif l_function_output.data_type = 'VARCHAR2' then
        l_on_rejected_output_type := 2;
      elsif l_function_output.data_type = 'DATE' then
        l_on_rejected_output_type := 4;
      else
        raise_application_error(-20042, 'unsupported output type (on_rejected) inside then call');
      end if;
      -- Check if need input at all.
      select count(*)
      into l_rejected_input_count
      from all_arguments
      where object_name = upper(on_rejected)
      and in_out = 'IN';
    end if;

    l_anonymous_plsql_block := 'declare
      l_dpr promise_result;
      l_do dbms_aq.dequeue_options_t;
      l_dmp dbms_aq.message_properties_t;
      l_fd boolean := true;
      l_dmh raw(16);
      l_dcn varchar2(30) := '''|| self.promise_name ||''';
      l_et exception;
      pragma exception_init(l_et, -25228);
      l_fe varchar2(4000);
      l_eo dbms_aq.enqueue_options_t;
      l_emp dbms_aq.message_properties_t;
      l_emh raw(16);
      l_epr promise_result;
      l_jqm promise_job_notify;
      l_poe varchar2(4000);
      l_po ';
    if self.typeval = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'number;';
    elsif self.typeval = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    elsif self.typeval = 4 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'date;';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block ||'
      l_ofr ';
    if l_on_fullfilled_output_type = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'number;';
    elsif l_on_fullfilled_output_type = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    elsif l_on_fullfilled_output_type = 4 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'date;';
    else
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
      l_orr ';
    if l_on_rejected_output_type = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'number;';
    elsif l_on_rejected_output_type = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    elsif l_on_rejected_output_type = 4 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'date;';
    else
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
    begin
      begin
        loop
          l_do.dequeue_mode := dbms_aq.browse;
          l_do.wait := dbms_aq.no_wait;
          l_do.visibility := dbms_aq.immediate;
          if l_fd then
            l_do.navigation := dbms_aq.first_message;
          else
            l_do.navigation := dbms_aq.next_message;
          end if;
          dbms_aq.dequeue(
            queue_name => ''promise_async_queue''
            , dequeue_options => l_do
            , message_properties => l_dmp
            , payload => l_dpr
            , msgid => l_dmh
          );
          if l_fd then
            l_fd := false;
          end if;
          if l_dpr.promise_name = l_dcn then
            if l_dpr.promise_result = ''SUCCESS'' then
              l_po := ';
      if self.typeval = 1 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'sys.anydata.accessNumber(l_dpr.promise_value);';
      elsif self.typeval = 2 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'sys.anydata.accessVarchar2(l_dpr.promise_value);';
      elsif self.typeval = 4 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'sys.anydata.accessDate(l_dpr.promise_value);';
      end if;
      l_anonymous_plsql_block := l_anonymous_plsql_block || '
            else
              l_poe := sys.anydata.accessVarchar2(l_dpr.promise_value);
            end if;
            exit;
          end if;
        end loop;
      exception
        when l_et then
          null;
      end;
      ';
      if on_fullfilled is not null then
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
      if l_dpr.promise_result = ''SUCCESS'' then
        ';
        if l_fulfilled_input_count > 0 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || 'l_ofr := '|| on_fullfilled ||'(l_po);';
        else
          l_anonymous_plsql_block := l_anonymous_plsql_block || 'l_ofr := '|| on_fullfilled ||';';
        end if;
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
        l_epr := promise_result';
        if l_on_fullfilled_output_type = 1 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 1, sys.anydata.convertnumber(l_ofr), '''|| self.promise_name ||''', '''|| to_char(self.chain_size) ||''', null);';
        elsif l_on_fullfilled_output_type = 2 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 2, sys.anydata.convertvarchar2(l_ofr), '''|| self.promise_name ||''', '''|| to_char(self.chain_size) ||''', null);';
        elsif l_on_fullfilled_output_type = 4 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 4, sys.anydata.convertdate(l_ofr), '''|| self.promise_name ||''', '''|| to_char(self.chain_size) ||''', null);';
        end if;
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
        l_jqm := promise_job_notify(''' || new_promise_name || ''', ''SUCCESS'');
      end if;
      ';
      end if;
      if on_rejected is not null then
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
      if l_dpr.promise_result = ''FAILURE'' then
        ';
        if l_rejected_input_count > 0 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || 'l_orr := '|| on_rejected ||'(l_po);';
        else
          l_anonymous_plsql_block := l_anonymous_plsql_block || 'l_orr := '|| on_rejected ||';';
        end if;
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
        l_epr := promise_result';
        if l_on_rejected_output_type = 1 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 1, sys.anydata.convertnumber(l_orr), '''|| self.promise_name ||''', '''|| to_char(self.chain_size) ||''', null);';
        elsif l_on_rejected_output_type = 2 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 2, sys.anydata.convertvarchar2(l_orr), '''|| self.promise_name ||''', '''|| to_char(self.chain_size) ||''', null);';
        elsif l_on_rejected_output_type = 4 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 4, sys.anydata.convertdate(l_orr), '''|| self.promise_name ||''', '''|| to_char(self.chain_size) ||''', null);';
        end if;
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
        l_jqm := promise_job_notify(''' || new_promise_name || ''', ''SUCCESS'');
      end if;';
      end if;
      l_anonymous_plsql_block := l_anonymous_plsql_block || '
      dbms_aq.enqueue(
        queue_name => ''promise_async_queue''
        , enqueue_options => l_eo
        , message_properties => l_emp
        , payload => l_epr
        , msgid => l_emh
      );
      dbms_aq.enqueue(
        queue_name => ''promise_job_queue''
        , enqueue_options => l_eo
        , message_properties => l_emp
        , payload => l_jqm
        , msgid => l_emh
      );
      commit;
      exception
        when others then
          l_fe := SQLCODE || ''-'' || SQLERRM;
          l_epr := promise_result(''' || new_promise_name || ''', ''FAILURE'', 2, sys.anydata.convertvarchar2(l_fe), '''|| self.promise_name ||''', '''|| to_char(self.chain_size) ||''', null);
          l_jqm := promise_job_notify(''' || new_promise_name || ''', ''FAILURE'');
          dbms_aq.enqueue(
            queue_name => ''promise_async_queue''
            , enqueue_options => l_eo
            , message_properties => l_emp
            , payload => l_epr
            , msgid => l_emh
          );
          dbms_aq.enqueue(
            queue_name => ''promise_job_queue''
            , enqueue_options => l_eo
            , message_properties => l_emp
            , payload => l_jqm
            , msgid => l_emh
          );
          commit;
    end;';

    return l_anonymous_plsql_block;

  end get_then_job_code;

  member function get_function_return(
    function_name       varchar2
  )
  return number

  as

    l_function_output             all_arguments%rowtype;

  begin

    select *
    into l_function_output
    from all_arguments
    where object_name = upper(function_name)
    and in_out = 'OUT';

    if l_function_output.data_type = 'NUMBER' then
      return 1;
    elsif l_function_output.data_type = 'VARCHAR2' then
      return 2;
    elsif l_function_output.data_type = 'DATE' then
      return 4;
    else
      raise_application_error(-20042, 'unsupported return datatype for on_success/on_reject function');
    end if;

  end get_function_return;

end;
/
