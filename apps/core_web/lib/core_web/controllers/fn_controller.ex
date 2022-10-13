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

defmodule CoreWeb.FnController do
  use CoreWeb, :controller

  alias Core.Domain.Api.FunctionRepo
  alias Core.Domain.Api.Invoker

  action_fallback(CoreWeb.FnFallbackController)

  def invoke(conn, params) do
    with {:ok, %{result: res}} <- Invoker.invoke(params) do
      render(conn, "invoke.json", result: res)
    end
  end

  def create(conn, %{"code" => %Plug.Upload{path: tmp_code_path}} = params) do
    func = params |> Map.put("code", File.read!(tmp_code_path))

    with {:ok, function_name} <- FunctionRepo.new(func) do
      conn
      |> put_status(:created)
      |> render("create.json", function_name: function_name)
    end
  end

  def create(_conn, _params) do
    {:error, :bad_params}
  end

  def delete(conn, params) do
    with {:ok, function_name} <- FunctionRepo.delete(params) do
      conn
      |> put_status(:no_content)
      |> render("delete.json", function_name: function_name)
    end
  end
end

defmodule CoreWeb.FnFallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """

  use Phoenix.Controller

  def call(conn, {:error, :bad_params}) do
    conn
    |> put_status(:bad_request)
    |> put_view(CoreWeb.ErrorView)
    |> render("400.json")
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(CoreWeb.ErrorView)
    |> render("function_not_found.json")
  end

  def call(conn, {:error, :no_workers}) do
    conn
    |> put_status(:service_unavailable)
    |> put_view(CoreWeb.ErrorView)
    |> render("no_workers.json")
  end

  def call(conn, {:error, :worker_error}) do
    conn
    |> put_status(:internal_server_error)
    |> put_view(CoreWeb.ErrorView)
    |> render("worker_error.json")
  end

  def call(conn, {:error, {kind, reason}}) when kind == :bad_insert or kind == :bad_delete do
    action =
      if kind == :bad_insert do
        "create"
      else
        "delete"
      end

    conn
    |> put_status(:service_unavailable)
    |> put_view(CoreWeb.ErrorView)
    |> render("db_aborted.json", action: action, reason: reason)
  end
end
