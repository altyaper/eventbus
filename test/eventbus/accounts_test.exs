defmodule Eventbus.AccountsTest do
  use Eventbus.DataCase, async: true

  import Eventbus.AccountsFixtures

  alias Eventbus.Accounts
  alias Eventbus.Accounts.{User, UserToken}

  describe "create_superadmin/1" do
    test "creates the first user as superadmin with a hashed password" do
      refute Accounts.any_users?()

      assert {:ok, %User{} = user} =
               Accounts.create_superadmin(%{
                 email: "  admin@example.com ",
                 password: valid_password()
               })

      assert user.email == "admin@example.com"
      assert user.role == "superadmin"
      assert user.confirmed_at
      assert user.accepted_terms_at
      assert is_binary(user.hashed_password)
      assert is_nil(user.password)
      assert Accounts.any_users?()
    end

    test "refuses once a user exists" do
      user_fixture()

      assert {:error, :already_set_up} =
               Accounts.create_superadmin(valid_user_attributes())
    end

    test "validates email and password" do
      assert {:error, changeset} =
               Accounts.create_superadmin(%{
                 email: "not an email",
                 password: "short",
                 password_confirmation: "different"
               })

      errors = errors_on(changeset)
      assert "must have the @ sign and no spaces" in errors.email
      assert "should be at least 12 character(s)" in errors.password
      assert "does not match password" in errors.password_confirmation
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns the user for valid credentials, case-insensitive email" do
      user = user_fixture(email: "jorge@example.com")

      assert %User{id: id} =
               Accounts.get_user_by_email_and_password(" JORGE@example.com", valid_password())

      assert id == user.id
    end

    test "returns nil for a wrong password or unknown user" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "wrong password!")
      refute Accounts.get_user_by_email_and_password("nobody@example.com", valid_password())
    end
  end

  test "emails are unique regardless of case" do
    user_fixture(email: "taken@example.com")

    assert {:error, changeset} =
             %User{}
             |> User.registration_changeset(valid_user_attributes(email: "TAKEN@example.com"))
             |> User.role_changeset("member")
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).email
  end

  describe "session tokens" do
    setup do
      user = user_fixture()
      %{user: user, token: Accounts.generate_user_session_token(user)}
    end

    test "resolve to the user", %{user: user, token: token} do
      assert Accounts.get_user_by_session_token(token).id == user.id
    end

    test "stop working once deleted", %{token: token} do
      assert :ok = Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end

    test "expire", %{token: token} do
      expired = DateTime.add(DateTime.utc_now(), -UserToken.session_validity_in_days() - 1, :day)
      Repo.update_all(UserToken, set: [inserted_at: expired])
      refute Accounts.get_user_by_session_token(token)
    end
  end
end
