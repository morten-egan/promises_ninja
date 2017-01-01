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
        else
          raise_application_error(-20042, 'only number or varchar2 output currently supported for promises');
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

  member procedure done_p (
    self                    in out      promise
    , on_fullfilled                     varchar2    default null
    , on_rejected                       varchar2    default null
  )

  as

    new_promise         promise;

  begin

    -- First check if promise has been validated.
    -- Do not allow an promise that has not been validated to be executed.
    if self.o_execute > 0 then
      -- Just re-use the then_p code, except we do not return anything.
      new_promise := self.then_p(on_fullfilled, on_rejected);
    else
      raise_application_error(-20042, 'cannot call done on promise that is not validated');
    end if;

  end done_p;

  member function then_p (
    self                  in out      promise
    , on_fullfilled                   varchar2      default null
    , on_rejected                     varchar2      default null
  )
  return promise

  as

    new_promise                 promise;
    l_anonymous_plsql_block     varchar2(32000);

  begin


    -- First check if promise has been validated.
    -- Do not allow to thenable a promise that has not been validated to be executed.
    if self.o_execute > 0 then
      -- Initiate the new promise that we will return.
      new_promise := promise();

      -- Poll for the answer and set if available.
      self.check_and_set_value;

      if self.state = 'fulfilled' then
        -- We already have the final result of the promise.
        -- Add new job directly, with promise value only if on_fulfilled is a real function.
        if on_fullfilled is not null then
          if self.on_is_function(on_fullfilled) then
            case self.typeval
              when 1 then new_promise := promise(on_fullfilled, sys.anydata.accessNumber(self.val));
              when 2 then new_promise := promise(on_fullfilled, sys.anydata.accessVarchar2(self.val));
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
        dbms_scheduler.create_job (
          job_name              =>      new_promise.promise_name || '_J'
          , job_type            =>      'PLSQL_BLOCK'
          , job_action          =>      l_anonymous_plsql_block
          , start_date          =>      systimestamp
          , event_condition     =>      'tab.user_data.promise_name = ''' || self.promise_name || ''''
          , queue_spec          =>      'promise_job_queue'
          , enabled             =>      true
        );
        -- When we have built the anonymous plsql and submitted the job
        -- we have also automatically validated the new promise. Set to validated.
        new_promise.o_execute := 1;
      end if;

      return new_promise;
    else
      raise_application_error(-20042, 'cannot call then on promise that is not validated');
    end if;

  end then_p;

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
            elsif l_promise_result.promise_result = 'FAILURE' then
              -- Set state to rejected and set the rejection result.
              self.state := 'rejected';
              self.val := l_promise_result.promise_value;
            end if;
          end if;
        end loop;

      end if;

      exception
        when l_exception_timeout then
          null;

  end check_and_set_value;

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

    if self.typeval = 1 then
      self.check_and_set_value;
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

    if self.typeval = 2 then
      self.check_and_set_value;
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

  member function get_exec_job_code
  return varchar2

  as

    l_anonymous_plsql_block       varchar2(32000);

  begin

    l_anonymous_plsql_block := 'declare
      l_full_error          varchar2(4000);
      l_enqueue_options     dbms_aq.enqueue_options_t;
      l_message_properties  dbms_aq.message_properties_t;
      l_message_recipients  dbms_aq.aq$_recipient_list_t;
      l_message_handle      raw(16);
      l_queue_message       promise_result;
      l_promise_result      ';
    if self.typeval = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'number;';
    elsif self.typeval = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    end if;
    if self.o_executor_typeval > 0 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '
      l_executor_var        ';
      if self.o_executor_typeval = 1 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'number := ' || to_char(sys.anydata.accessNumber(self.o_executor_val)) || ';';
      elsif self.o_executor_typeval = 2 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000) := ''' || to_char(sys.anydata.accessVarchar2(self.o_executor_val)) || ''';';
      end if;
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
      begin
        l_promise_result := ';
    if self.o_executor_typeval > 0 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || self.o_executor || '(l_executor_var);';
    else
      l_anonymous_plsql_block := l_anonymous_plsql_block || self.o_executor || ';';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
        l_queue_message := promise_result';
    if self.typeval = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '(''' || self.promise_name || ''', ''SUCCESS'', 1, sys.anydata.convertnumber(l_promise_result));';
    elsif self.typeval = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '(''' || self.promise_name || ''', ''SUCCESS'', 2, sys.anydata.convertvarchar2(l_promise_result));';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
        dbms_aq.enqueue(
          queue_name            =>    ''promise_async_queue''
          , enqueue_options     =>    l_enqueue_options
          , message_properties  =>    l_message_properties
          , payload             =>    l_queue_message
          , msgid               =>    l_message_handle
        );
        commit;

        exception
          when others then
            l_full_error := SQLCODE || ''-'' || SQLERRM;
            l_queue_message := promise_result(''' || self.promise_name || ''', ''FAILURE'', 2, sys.anydata.convertvarchar2(l_full_error));
            dbms_aq.enqueue(
              queue_name            =>    ''promise_async_queue''
              , enqueue_options     =>    l_enqueue_options
              , message_properties  =>    l_message_properties
              , payload             =>    l_queue_message
              , msgid               =>    l_message_handle
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
      else
        raise_application_error(-20042, 'unsupported output type (on_fulfilled) inside then call');
      end if;
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
      else
        raise_application_error(-20042, 'unsupported output type (on_rejected) inside then call');
      end if;
    end if;

    l_anonymous_plsql_block := 'declare
      -- Dequeue variables
      l_d_promise_result          promise_result;
      l_dequeue_options           dbms_aq.dequeue_options_t;
      l_d_message_properties      dbms_aq.message_properties_t;
      l_first_dequeue             boolean := true;
      l_d_message_handle          raw(16);
      l_d_check_name              varchar2(30) := '''|| self.promise_name ||''';
      -- Exceptions
      l_exception_timeout         exception;
      pragma exception_init(l_exception_timeout, -25228);
      l_full_error                varchar2(4000);
      -- Enqueue variables.
      l_enqueue_options           dbms_aq.enqueue_options_t;
      l_e_message_properties      dbms_aq.message_properties_t;
      l_e_message_handle          raw(16);
      l_e_promise_result          promise_result;
      -- Call variables.
      l_promise_output_error      varchar2(4000);
      l_promise_output            ';
    if self.typeval = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'number;';
    elsif self.typeval = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block ||'
      l_on_fullfill_result        ';
    if l_on_fullfilled_output_type = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'number;';
    elsif l_on_fullfilled_output_type = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    else
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
      l_on_rejected_result        ';
    if l_on_rejected_output_type = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'number;';
    elsif l_on_rejected_output_type = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    else
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
    begin
      -- First we need to fetch the message with the result. We know it is there.
      begin
        loop
          l_dequeue_options.dequeue_mode := dbms_aq.browse;
          l_dequeue_options.wait := dbms_aq.no_wait;
          l_dequeue_options.visibility := dbms_aq.immediate;
          if l_first_dequeue then
            l_dequeue_options.navigation := dbms_aq.first_message;
          else
            l_dequeue_options.navigation := dbms_aq.next_message;
          end if;
          dbms_aq.dequeue(
            queue_name              =>    ''promise_async_queue''
            , dequeue_options       =>    l_dequeue_options
            , message_properties    =>    l_d_message_properties
            , payload               =>    l_d_promise_result
            , msgid                 =>    l_d_message_handle
          );
          if l_first_dequeue then
            l_first_dequeue := false;
          end if;
          if l_d_promise_result.promise_name = l_d_check_name then
            -- We have the right promise value. Use as input to new promise call.
            if l_d_promise_result.promise_result = ''SUCCESS'' then
              l_promise_output := ';
      if self.typeval = 1 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'sys.anydata.accessNumber(l_d_promise_result.promise_value);';
      elsif self.typeval = 2 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'sys.anydata.accessVarchar2(l_d_promise_result.promise_value);';
      end if;
      l_anonymous_plsql_block := l_anonymous_plsql_block || '
            else
              l_promise_output_error := sys.anydata.accessVarchar2(l_d_promise_result.promise_value);
            end if;
            -- We have what we need. Exit loop
            exit;
          end if;
        end loop;
      exception
        when l_exception_timeout then
          null;
      end;
      -- Now we have the result. Run either fulfill or reject depending on result.';
      if on_fullfilled is not null then
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
      if l_d_promise_result.promise_result = ''SUCCESS'' then
        l_on_fullfill_result := '|| on_fullfilled ||'(l_promise_output);
        l_e_promise_result := promise_result';
        if l_on_fullfilled_output_type = 1 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 1, sys.anydata.convertnumber(l_on_fullfill_result));';
        elsif l_on_fullfilled_output_type = 2 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 2, sys.anydata.convertvarchar2(l_on_fullfill_result));';
        end if;
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
      end if;
      ';
      end if;
      if on_rejected is not null then
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
      if l_d_promise_result.promise_result = ''FAILURE'' then
        l_on_rejected_result := '|| on_rejected ||'(l_promise_output);
        l_e_promise_result := promise_result';
        if l_on_rejected_output_type = 1 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 1, sys.anydata.convertnumber(l_on_rejected_result));';
        elsif l_on_rejected_output_type = 2 then
          l_anonymous_plsql_block := l_anonymous_plsql_block || '('''|| new_promise_name ||''', ''SUCCESS'', 2, sys.anydata.convertvarchar2(l_on_rejected_result));';
        end if;
        l_anonymous_plsql_block := l_anonymous_plsql_block || '
      end if;';
      end if;

      l_anonymous_plsql_block := l_anonymous_plsql_block || '
      -- Enqueue the result message.
      dbms_aq.enqueue(
        queue_name            =>    ''promise_async_queue''
        , enqueue_options     =>    l_enqueue_options
        , message_properties  =>    l_e_message_properties
        , payload             =>    l_e_promise_result
        , msgid               =>    l_e_message_handle
      );
      commit;

      exception
        when others then
          l_full_error := SQLCODE || ''-'' || SQLERRM;
          l_e_promise_result := promise_result(''' || new_promise_name || ''', ''FAILURE'', 2, sys.anydata.convertvarchar2(l_full_error));
          dbms_aq.enqueue(
            queue_name            =>    ''promise_async_queue''
            , enqueue_options     =>    l_enqueue_options
            , message_properties  =>    l_e_message_properties
            , payload             =>    l_e_promise_result
            , msgid               =>    l_e_message_handle
          );
          commit;
    end;';

    return l_anonymous_plsql_block;

  end get_then_job_code;

end;
/
