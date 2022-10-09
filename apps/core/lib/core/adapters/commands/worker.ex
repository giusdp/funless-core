# Copyright 2022 Giuseppe De Palma, Matteo Trentin
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Core.Adapters.Commands.Worker do
  @moduledoc """
  Adapter to send commands to a worker actor.
  Currently implemented commands: invocation.
  """
  require Logger
  alias Core.Domain.FunctionStruct
  alias Core.Domain.InvokeResult

  @behaviour Core.Domain.Ports.Commands

  # Possible replies:
  # {:ok, result}
  # :code_not_found in this case re-do the invocation passing the code
  # {:error, atom()} mainly from the worker nifs
  # {:error, %{"error" => msg}} a map with the reason

  # Handle the second type of error by logging and transforming it in :worker_error for the api
  # Handle the third type of error by logging the message and transforming it in :worker_error for the api
  @impl true
  def send_invoke(worker, name, ns, args) do
    worker_addr = {:worker, worker}
    cmd = {:invoke, %{name: name, namespace: ns}, args}
    Logger.info("sending invoke for #{name} to #{inspect(worker_addr)}")

    case GenServer.call(worker_addr, cmd, 30_000) do
      {:ok, result} -> {:ok, %InvokeResult{result: result}}
      {:warn, :code_not_found} -> {:warn, :code_not_found}
      {:error, err} -> {:error, err}
    end
  end

  @impl true
  def send_invoke_with_code(worker, %FunctionStruct{} = function, args) do
    worker_addr = {:worker, worker}
    cmd = {:invoke, function, args}
    Logger.info("sending invoke with code for #{function.name} to #{inspect(worker_addr)}")

    case GenServer.call(worker_addr, cmd, 30_000) do
      {:ok, result} -> {:ok, %InvokeResult{result: result}}
      {:error, err} -> {:error, err}
    end
  end
end