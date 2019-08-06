CREATE TABLE portfolio_users
(
  name VARCHAR(64) NOT NULL,
  password VARCHAR(64) NOT NULL,
    constraint long_passwd_p CHECK (password LIKE '________%'),
  email VARCHAR(256) NOT NULL primary key
    constraint email_ok_p CHECK (email LIKE '%@%')
);

--- when potential user creates a new account
--- ExecSQL($dbuser, $dbpasswd, "INSERT INTO portfolio_users VALUES (?, ?, ?), undef, $username, $email, $passwd))

CREATE TABLE portfolio_portfolio
(
  ID NUMBER NOT NULL primary key,
  cash NUMBER NOT NULL
    constraint cash_nonnegative CHECK (cash >= 0),
  user_email VARCHAR(256) NOT NULL references portfolio_users(email)
);



CREATE SEQUENCE seq_portfolio
  MINVALUE 1
  START WITH 1
  INCREMENT BY 1
  CACHE 10;
--- when user deposits or withdraw cash from the cash account
--- if the user make deposit/withdrawal from/for outside sources
--- calculate $newCash value
--- ExecSQL($dbuser, $dbpasswd, "UPDATE portfolio_portfolio SET cash=? where ID=?", undef, $newCash, $portfolioID))
--
--- if the user make inter-accounts deposit/withdrawal
--- calcualte $newCash1, $newCash2 values
--- ExecSQL($dbuser, $dbpasswd, "UPDATE portfolio_portfolio SET cash=? where ID=?", undef, $newCash1, $portfolioID1))
--- ExecSQL($dbuser, $dbpasswd, "UPDATE portfolio_portfolio SET cash=? where ID=?", undef, $newCash2, $portfolioID2))

--- when the user purchases/sells a stock with $stockSymbol
--- obtain the $tranShare (transcation shares) from the front-end (user-specified)
--- obtain the transaction price of the stock $currPrice from quote.pl
--- calculate the $tranValue (transaction value) (tranValue = tranShare * currPrice)
--- $currCash value obtained from $currCash = ExecSQL($dbuser, $dbpasswd, "SELECT cash from portfolio_portfolio where ID=?", undef, $portfolioID)
--- calculate $newCash value (newCash = currCash +/- tranValue)
--- ExecSQL($dbuser, $dbpasswd, "UPDATE portfolio_portfolio SET cash=? where ID=?", undef, $newCash, $portfolioID))


CREATE TABLE stocks
(
  symbol VARCHAR2(16) NOT NULL,
  timestamp NUMBER NOT NULL, 
  open NUMBER NOT NULL
    constraint open_nonnegative CHECK (open >= 0),
  high NUMBER NOT NULL
    constraint high_nonnegative CHECK (high >= 0),
  low NUMBER NOT NULL
    constraint low_nonnegative CHECK (low >= 0),
  close NUMBER NOT NULL
    constraint close_nonnegative CHECK (close >= 0),
  volume NUMBER NOT NULL
    constraint volume_nonnegative CHECK (volume >= 0)
);


-- The PRIMARY KEY was done wrong. correction
ALTER TABLE stocks
ADD CONSTRAINT daily_stock PRIMARY KEY (symbol, timestamp);

-- 
-- Copying data from cs339.StocksDaily...

-- INSERT INTO stocks SELECT * FROM cs339.StocksDaily; 

--- after the market closes on each trading day, say 6pm ETS
--- for each active stock $stockSymbol, 
--- 1) obtain values of $timestamp, $open, $high, $low, $close, $volume through quote.pl or quotehist.pl
--- 2) store new daily stocks information into the stocks table
--- ExecSQL($dbuser, $dbpasswd, "UPDATE stocks SET timestamp=? and open=? and high=? and low=? and close=? and volume=? where symbol=?", undef, $timestamp, $open, $high, $low, $close, $volume, $stockSymbol))

CREATE TABLE stock_holdings
(
  portfolio_ID NUMBER NOT NULL references portfolio_portfolio(ID),
  symbol VARCHAR2(16) NOT NULL,
  shares NUMBER NOT NULL 
    constraint shares_nonnegative CHECK (shares >= 0)
);

--- when the user purchases/sells a stock with $stockSymbol
--- calculate $newShares (new shares = old shares +/- transaction shares)
--- ExecSQL($dbuser, $dbpasswd, "UPDATE stock_holdings SET shares=? where symbol=?", undef, $newShares, $stockSymbol))

ALTER TABLE stock_holdings  
ADD buy_price NUMBER NOT NULL;

CREATE VIEW all_stocks AS
SELECT * FROM cs339.StocksDaily UNION ALL
SELECT * FROM stocks;
-- ORDER BY timestamp; 


quit;
