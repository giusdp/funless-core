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

defmodule CoreWeb.FnControllerTest do
  use CoreWeb.ConnCase, async: true

  setup do
    Core.FunctionStore.Mock
    |> Mox.stub_with(Core.Adapters.FunctionStore.Test)

    Core.Commands.Mock
    |> Mox.stub_with(Core.Adapters.Commands.Test)

    Core.Cluster.Mock
    |> Mox.stub_with(Core.Adapters.Cluster.Test)

    :ok
  end

  describe "POST /v1/fn/invoke" do
    test "success: should return 200 with good request", %{conn: conn} do
      Core.Cluster.Mock |> Mox.expect(:all_nodes, fn -> [:worker@localhost] end)

      Core.Commands.Mock
      |> Mox.expect(:send_invoke, fn _, _, _, _ -> {:ok, %{result: "Hello, World!"}} end)

      conn = post(conn, "/v1/fn/invoke", %{module: "_", function: "hello", args: %{}})

      assert %{"result" => "Hello, World!"} = json_response(conn, 200)
    end

    test "error: should return 404 when the required function is not found", %{conn: conn} do
      Core.Cluster.Mock |> Mox.expect(:all_nodes, fn -> [:worker@localhost] end)
      Core.FunctionStore.Mock |> Mox.expect(:exists?, fn _, _ -> false end)

      conn = post(conn, "/v1/fn/invoke", %{function: "hello"})

      expected = %{
        "errors" => %{"detail" => "Failed to invoke function: not found in given module"}
      }

      assert json_response(conn, 404) == expected
    end

    test "error: should return 400 bad request when bad parameters", %{conn: conn} do
      conn = post(conn, "/v1/fn/invoke", %{bad: "param"})
      expected = %{"errors" => %{"detail" => "Failed to perform operation: bad request"}}
      assert json_response(conn, 400) == expected
    end

    test "error: should return 400 when missing parameters", %{conn: conn} do
      conn = post(conn, "/v1/fn/invoke", %{module: "a_ns"})
      expected = %{"errors" => %{"detail" => "Failed to perform operation: bad request"}}
      assert json_response(conn, 400) == expected
    end

    test "error: should return 500 when some worker error occurs", %{conn: conn} do
      Core.Cluster.Mock |> Mox.expect(:all_nodes, fn -> [:worker@localhost] end)

      Core.Commands.Mock
      |> Mox.expect(:send_invoke, fn _, _, _, _ -> {:error, {:exec_error, "some error"}} end)

      conn = post(conn, "/v1/fn/invoke", %{function: "test", code: ""})
      expected = %{"errors" => %{"detail" => "Failed to invoke function: some error"}}
      assert json_response(conn, 500) == expected
    end

    test "error: should return 503 when invocation with no workers available fails", %{conn: conn} do
      conn = post(conn, "/v1/fn/invoke", %{function: "test", code: ""})
      expected = %{"errors" => %{"detail" => "Failed to invoke function: no worker available"}}
      assert json_response(conn, 503) == expected
    end
  end

  describe "POST /v1/fn/create" do
    test "success: should return 200 when the creation is successful", %{conn: conn} do
      upload = %Plug.Upload{
        path: "test/support/fixtures/test_code.txt",
        filename: "test_code.txt"
      }

      conn = post(conn, "/v1/fn/create", %{name: "hello", code: upload})

      expected = %{"result" => "hello"}
      assert json_response(conn, 201) == expected
    end

    test "error: should returns 400 when given invalid parameters", %{conn: conn} do
      conn = post(conn, "/v1/fn/create", %{bad: "params"})
      expected = %{"errors" => %{"detail" => "Failed to perform operation: bad request"}}
      assert json_response(conn, 400) == expected
    end

    test "error: should returns 400 when missing parameters", %{conn: conn} do
      conn = post(conn, "/v1/fn/create", %{name: "a_function"})
      expected = %{"errors" => %{"detail" => "Failed to perform operation: bad request"}}
      assert json_response(conn, 400) == expected
    end

    test "error: should return 503 when the underlying storage transaction fails", %{conn: conn} do
      Core.FunctionStore.Mock
      |> Mox.expect(:insert_function, fn _ -> {:error, {:aborted, "some reason"}} end)

      upload = %Plug.Upload{
        path: "test/support/fixtures/test_code.txt",
        filename: "test_code.txt"
      }

      conn = post(conn, "/v1/fn/create", %{name: "hello", code: upload})

      expected = %{
        "errors" => %{"detail" => "Failed to create function: some reason"}
      }

      assert json_response(conn, 503) == expected
    end
  end

  describe "DELETE /v1/fn/delete" do
    test "success: should return 200 when the deletion is successful", %{conn: conn} do
      conn = delete(conn, "/v1/fn/delete", %{name: "hello", module: "ns"})

      expected = %{"result" => "hello"}
      assert json_response(conn, 200) == expected
    end

    test "error: should return 400 when given bad parameters", %{conn: conn} do
      conn = delete(conn, "/v1/fn/delete", %{bad: "params"})
      expected = %{"errors" => %{"detail" => "Failed to perform operation: bad request"}}
      assert json_response(conn, 400) == expected
    end

    test "error: should return 400 when missing parameters", %{conn: conn} do
      conn = delete(conn, "/v1/fn/delete", %{module: "a_ns"})
      expected = %{"errors" => %{"detail" => "Failed to perform operation: bad request"}}

      assert json_response(conn, 400) == expected
    end

    test "error: should return 404 when the function is not found in the storage", %{conn: conn} do
      Core.FunctionStore.Mock
      |> Mox.expect(:delete_function, fn _, _ -> {:error, {:bad_delete, :not_found}} end)

      conn = delete(conn, "/v1/fn/delete", %{name: "hello", module: "ns"})

      expected = %{
        "errors" => %{"detail" => "Failed to delete function: not found"}
      }

      assert json_response(conn, 404) == expected
    end

    test "error: should return 503 when the underlying storage transaction fails", %{conn: conn} do
      Core.FunctionStore.Mock
      |> Mox.expect(:delete_function, fn _, _ -> {:error, {:aborted, "some reason"}} end)

      conn = delete(conn, "/v1/fn/delete", %{name: "hello", module: "ns"})

      expected = %{
        "errors" => %{"detail" => "Failed to delete function: some reason"}
      }

      assert json_response(conn, 503) == expected
    end
  end

  describe "GET /v1/fn/list/:module" do
    test "success: should return 200 when the list is returned successfully", %{conn: conn} do
      conn = get(conn, "/v1/fn/list/ns")

      expected = %{"result" => []}
      assert json_response(conn, 200) == expected
    end

    test "error: should raise an error when no module is given", %{conn: conn} do
      assert_raise Phoenix.Router.NoRouteError, fn ->
        _conn = get(conn, "/v1/fn/list/")
      end
    end

    test "error: should return 503 when the underlying storage transaction fails", %{conn: conn} do
      Core.FunctionStore.Mock
      |> Mox.expect(:list_functions, fn _ -> {:error, {:aborted, "some reason"}} end)

      conn = get(conn, "/v1/fn/list/ns")

      expected = %{
        "errors" => %{"detail" => "Failed to list functions: some reason"}
      }

      assert json_response(conn, 503) == expected
    end
  end

  describe "Invalid json handling" do
    test "should return a 400 code with a related message", %{conn: conn} do
      body = %{"name" => "hello"}
      invalid_body = Jason.encode!(body) <> ","

      assert_error_sent(400, fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/v1/fn/create", invalid_body)
      end)
    end

    test "internal crashes should return a 500 code with a generic message", %{conn: conn} do
      Core.FunctionStore.Mock
      |> Mox.expect(:insert_function, fn _ ->
        raise "some error"
        {:ok, "hello"}
      end)

      response =
        assert_error_sent(500, fn ->
          upload = %Plug.Upload{
            path: "test/support/fixtures/test_code.txt",
            filename: "test_code.txt"
          }

          conn
          |> post("/v1/fn/create", %{name: "hello", module: "ns", code: upload})
        end)

      assert {500, [_h | _t], "{\"errors\":{\"detail\":\"Internal Server Error\"}}"} = response
    end
  end
end