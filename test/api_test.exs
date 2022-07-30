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

defmodule ApiTest do
  use ExUnit.Case, async: true

  alias Worker.Domain.Api
  alias Worker.Domain.FunctionStruct
  import Mox, only: [verify_on_exit!: 1]

  setup :verify_on_exit!

  setup_all do
    function = %FunctionStruct{
      name: "hellojs",
      image: "node:lts-alpine",
      main_file: "/opt/index.js",
      archive: "js/hello.tar.gz"
    }

    %{function: function}
  end

  describe "main Worker.Api functions" do
    setup do
      Worker.Runtime.Mock |> Mox.stub_with(Worker.Adapters.Runtime.Test)
      Worker.RuntimeTracker.Mock |> Mox.stub_with(Worker.Adapters.RuntimeTracker.Test)
      :ok
    end

    test "prepare_runtime should return {:error, err} when the underlying functions encounter errors",
         %{function: function} do
      Worker.Runtime.Mock
      |> Mox.stub(:prepare, fn _function, _runtime ->
        {:error, "generic error"}
      end)

      assert Api.prepare_runtime(function) == {:error, "generic error"}
    end

    test "prepare_runtime should not call the function storage when the runtime is not created successfully",
         %{function: function} do
      Worker.Runtime.Mock
      |> Mox.stub(:prepare, fn _function, _runtime ->
        {:error, "generic error"}
      end)

      Worker.RuntimeTracker.Mock
      |> Mox.expect(:insert_runtime, 0, &Worker.Adapters.RuntimeTracker.Test.insert_runtime/2)

      assert Api.prepare_runtime(function) == {:error, "generic error"}
    end

    test "invoke_function should return {:ok, result map} from the called function when no error is present",
         %{function: function} do
      assert {:ok, %{"result" => "output"}} == Api.invoke_function(function)
    end

    test "invoke_function should return {:error, err} when running the given function raises an error",
         %{
           function: function
         } do
      Worker.Runtime.Mock
      |> Mox.stub(:run_function, fn _function, _args, _runtime ->
        {:error, "generic error"}
      end)

      assert {:error, "generic error"} == Api.invoke_function(function)
    end

    test "invoke_function should return {:error, err} when no runtime available and its creation fails",
         %{
           function: function
         } do
      Worker.RuntimeTracker.Mock |> Mox.expect(:get_runtimes, fn _ -> [] end)

      Worker.Runtime.Mock
      |> Mox.expect(:prepare, fn _, _ -> {:error, "creation error"} end)

      assert {:error, "creation error"} == Api.invoke_function(function)
    end

    test "cleanup should return {:ok, runtime} when a runtime is found and deleted for the given function",
         %{function: function} do
      [runtime | _] = Worker.RuntimeTracker.Mock.get_runtimes(function.name)

      assert Api.cleanup(function) == {:ok, runtime}
    end

    test "cleanup should return {:error, err} when no runtime is found for the given function",
         %{function: function} do
      Worker.RuntimeTracker.Mock |> Mox.expect(:get_runtimes, fn _ -> [] end)

      assert {:error, "no runtime found to cleanup"} == Api.cleanup(function)
    end

    test "cleanup_all should return {:ok, []} when all runtimes are deleted without errors for the given function",
         %{function: function} do
      Worker.RuntimeTracker.Mock
      |> Mox.expect(:get_runtimes, fn _ ->
        [
          %Worker.Domain.RuntimeStruct{name: "runtime1", host: "localhost", port: "8080"},
          %Worker.Domain.RuntimeStruct{name: "runtime2", host: "localhost", port: "8081"}
        ]
      end)

      assert Api.cleanup_all(function) == {:ok, []}
    end

    test "cleanup_all should return {:error, err} when no runtime is found for the given function",
         %{function: function} do
      Worker.RuntimeTracker.Mock |> Mox.expect(:get_runtimes, fn _ -> [] end)

      assert {:error, "no runtime found to cleanup"} == Api.cleanup_all(function)
    end

    test "cleanup_all should return {:error, [{runtime, err}, ... ]} when errors are encountered while deleting the runtimes",
         %{function: function} do
      Worker.RuntimeTracker.Mock
      |> Mox.expect(:get_runtimes, fn _ ->
        [
          %Worker.Domain.RuntimeStruct{name: "runtime1", host: "localhost", port: "8080"},
          %Worker.Domain.RuntimeStruct{name: "runtime2", host: "localhost", port: "8081"}
        ]
      end)

      Worker.Runtime.Mock
      |> Mox.expect(
        :cleanup,
        2,
        fn r ->
          case r do
            %Worker.Domain.RuntimeStruct{name: "runtime1"} -> {:error, "error"}
            _ -> {:ok, r}
          end
        end
      )

      assert {:error,
              [
                {"runtime1", "error"}
              ]} ==
               Api.cleanup_all(function)
    end
  end
end
