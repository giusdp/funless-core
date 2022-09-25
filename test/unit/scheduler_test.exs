# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
defmodule SchedulerTest do
  use ExUnit.Case, async: true

  alias Core.Domain.Scheduler

  import Mox

  setup :verify_on_exit!

  describe "Scheduler" do
    setup do
      Core.Telemetry.Api.Mock |> Mox.stub_with(Core.Adapters.Telemetry.Native.Test)
      :ok
    end

    test "select should return the worker when list has only one element" do
      expected = :worker
      w_nodes = [:worker]
      workers = Scheduler.select(w_nodes)

      assert workers == expected
    end

    test "select should return :no_workers when empty list" do
      expected = :no_workers
      w_nodes = []
      workers = Scheduler.select(w_nodes)

      assert workers == expected
    end

    test "select should return worker with fewer cpu utilization" do
      Core.Telemetry.Api.Mock
      |> expect(:resources, 2, fn w ->
        case w do
          :worker1 -> {:ok, %{cpu: 10}}
          :worker2 -> {:ok, %{cpu: 5}}
        end
      end)

      selected = Scheduler.select([:worker1, :worker2])
      assert selected == :worker2
    end
  end
end