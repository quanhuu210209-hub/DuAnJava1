


/* =====================================================================
   HỆ THỐNG BÁN LINH KIỆN MÁY TÍNH ONLINE & OFFLINE
   CSDL SQL Server - xây dựng từ Báo cáo khảo sát & phân tích yêu cầu v1.0
   Vai trò: Admin | Staff (Nhân viên)
            | Customer (Người dùng) | Guest (khách vãng lai - không lưu tài khoản)
   Cách chạy: mở bằng SSMS -> Execute (F5) trên một server SQL Server 2016+
   ===================================================================== */

IF DB_ID(N'ShopLinhKienMayTinh') IS NULL
    CREATE DATABASE ShopLinhKienMayTinh;
GO
USE ShopLinhKienMayTinh;
GO

/* =====================================================================
   1. NHÓM TÀI KHOẢN - PHÂN QUYỀN
   ===================================================================== */

-- Vai trò (Admin, Staff, Customer). Guest không có tài khoản nên không lưu.
CREATE TABLE dbo.Roles (
    RoleID      INT IDENTITY(1,1) CONSTRAINT PK_Roles PRIMARY KEY,
    RoleCode    VARCHAR(20)   NOT NULL CONSTRAINT UQ_Roles_Code UNIQUE,
    RoleName    NVARCHAR(50)  NOT NULL,
    Description NVARCHAR(255) NULL
);
GO

-- Tài khoản đăng nhập của mọi vai trò (STT 1, 2, 23, 29)
CREATE TABLE dbo.Users (
    UserID        INT IDENTITY(1,1) CONSTRAINT PK_Users PRIMARY KEY,
    RoleID        INT           NOT NULL CONSTRAINT FK_Users_Roles REFERENCES dbo.Roles(RoleID),
    FullName      NVARCHAR(100) NOT NULL,
    Email         VARCHAR(150)  NULL,
    Phone         VARCHAR(20)   NULL,
    PasswordHash  VARCHAR(255)  NOT NULL,
    IsVerified    BIT           NOT NULL CONSTRAINT DF_Users_Verified DEFAULT 0,  -- đã xác thực email/SĐT
    IsActive      BIT           NOT NULL CONSTRAINT DF_Users_Active DEFAULT 1,    -- khoá/mở khoá, vô hiệu hoá nhân viên nghỉ việc
    LastLoginAt   DATETIME2(0)  NULL,
    CreatedAt     DATETIME2(0)  NOT NULL CONSTRAINT DF_Users_Created DEFAULT SYSDATETIME(),
    CONSTRAINT CK_Users_EmailOrPhone CHECK (Email IS NOT NULL OR Phone IS NOT NULL)
);
GO
CREATE UNIQUE INDEX UX_Users_Email ON dbo.Users(Email) WHERE Email IS NOT NULL;
CREATE UNIQUE INDEX UX_Users_Phone ON dbo.Users(Phone) WHERE Phone IS NOT NULL;
CREATE INDEX IX_Users_Role ON dbo.Users(RoleID);
GO

-- Token xác thực email/SĐT, quên mật khẩu (STT 1, 2)
CREATE TABLE dbo.UserTokens (
    TokenID    BIGINT IDENTITY(1,1) CONSTRAINT PK_UserTokens PRIMARY KEY,
    UserID     INT          NOT NULL CONSTRAINT FK_UserTokens_Users REFERENCES dbo.Users(UserID) ON DELETE CASCADE,
    TokenType  VARCHAR(20)  NOT NULL CONSTRAINT CK_UserTokens_Type CHECK (TokenType IN ('VerifyEmail','VerifyPhone','ResetPassword')),
    TokenValue VARCHAR(100) NOT NULL,
    ExpiresAt  DATETIME2(0) NOT NULL,
    UsedAt     DATETIME2(0) NULL,
    CreatedAt  DATETIME2(0) NOT NULL CONSTRAINT DF_UserTokens_Created DEFAULT SYSDATETIME()
);
CREATE INDEX IX_UserTokens_Value ON dbo.UserTokens(TokenValue);
GO

-- Khách hàng: gồm khách có tài khoản website (UserID có giá trị)
-- và khách mua lần đầu tại quầy chưa có tài khoản (UserID = NULL) - STT 18
CREATE TABLE dbo.Customers (
    CustomerID  INT IDENTITY(1,1) CONSTRAINT PK_Customers PRIMARY KEY,
    UserID      INT           NULL CONSTRAINT FK_Customers_Users REFERENCES dbo.Users(UserID),
    FullName    NVARCHAR(100) NOT NULL,
    Phone       VARCHAR(20)   NULL,
    Email       VARCHAR(150)  NULL,
    CreatedBy   INT           NULL CONSTRAINT FK_Customers_CreatedBy REFERENCES dbo.Users(UserID), -- nhân viên tạo tại quầy
    CreatedAt   DATETIME2(0)  NOT NULL CONSTRAINT DF_Customers_Created DEFAULT SYSDATETIME()
);
CREATE UNIQUE INDEX UX_Customers_User  ON dbo.Customers(UserID) WHERE UserID IS NOT NULL;
CREATE INDEX IX_Customers_Phone ON dbo.Customers(Phone);
CREATE INDEX IX_Customers_Name  ON dbo.Customers(FullName);
GO

-- Sổ địa chỉ giao hàng (STT 9)
CREATE TABLE dbo.CustomerAddresses (
    AddressID     INT IDENTITY(1,1) CONSTRAINT PK_CustomerAddresses PRIMARY KEY,
    CustomerID    INT           NOT NULL CONSTRAINT FK_Addr_Customers REFERENCES dbo.Customers(CustomerID) ON DELETE CASCADE,
    ReceiverName  NVARCHAR(100) NOT NULL,
    ReceiverPhone VARCHAR(20)   NOT NULL,
    Province      NVARCHAR(100) NOT NULL,
    District      NVARCHAR(100) NOT NULL,
    Ward          NVARCHAR(100) NULL,
    AddressLine   NVARCHAR(250) NOT NULL,
    IsDefault     BIT           NOT NULL CONSTRAINT DF_Addr_Default DEFAULT 0
);
-- Mỗi khách chỉ có 1 địa chỉ mặc định
CREATE UNIQUE INDEX UX_Addr_OneDefault ON dbo.CustomerAddresses(CustomerID) WHERE IsDefault = 1;
GO

/* =====================================================================
   2. NHÓM DANH MỤC - SẢN PHẨM GỐC - GIÁ (Admin quản lý, dùng chung)
   ===================================================================== */

CREATE TABLE dbo.Categories (
    CategoryID   INT IDENTITY(1,1) CONSTRAINT PK_Categories PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL CONSTRAINT UQ_Categories_Name UNIQUE,
    Description  NVARCHAR(255) NULL,
    IsActive     BIT NOT NULL CONSTRAINT DF_Categories_Active DEFAULT 1
);
GO
CREATE TABLE dbo.Brands (
    BrandID   INT IDENTITY(1,1) CONSTRAINT PK_Brands PRIMARY KEY,
    BrandName NVARCHAR(100) NOT NULL CONSTRAINT UQ_Brands_Name UNIQUE,
    LogoUrl   VARCHAR(300)  NULL,
    IsActive  BIT NOT NULL CONSTRAINT DF_Brands_Active DEFAULT 1
);
GO

-- Sản phẩm gốc dùng chung cho toàn hệ thống (STT 30).
-- Price: giá bán thống nhất cho website và bán tại quầy (STT 31).
CREATE TABLE dbo.Products (
    ProductID       INT IDENTITY(1,1) CONSTRAINT PK_Products PRIMARY KEY,
    SKU             VARCHAR(50)   NOT NULL CONSTRAINT UQ_Products_SKU UNIQUE,
    ProductName     NVARCHAR(250) NOT NULL,
    CategoryID      INT NOT NULL CONSTRAINT FK_Products_Categories REFERENCES dbo.Categories(CategoryID),
    BrandID         INT NOT NULL CONSTRAINT FK_Products_Brands REFERENCES dbo.Brands(BrandID),
    Description     NVARCHAR(MAX) NULL,
    Price           DECIMAL(18,0) NOT NULL CONSTRAINT CK_Products_Price CHECK (Price >= 0),
    WarrantyMonths  INT           NOT NULL CONSTRAINT DF_Products_Warranty DEFAULT 12 CONSTRAINT CK_Products_Warranty CHECK (WarrantyMonths >= 0),
    ThumbnailUrl    VARCHAR(300)  NULL,
    Status          VARCHAR(20)   NOT NULL CONSTRAINT DF_Products_Status DEFAULT 'Active'
                    CONSTRAINT CK_Products_Status CHECK (Status IN ('Active','Hidden','Discontinued')),
    CreatedAt       DATETIME2(0)  NOT NULL CONSTRAINT DF_Products_Created DEFAULT SYSDATETIME(),
    UpdatedAt       DATETIME2(0)  NULL
);
CREATE INDEX IX_Products_Cat_Brand ON dbo.Products(CategoryID, BrandID) INCLUDE (Price, Status);
CREATE INDEX IX_Products_Name ON dbo.Products(ProductName);
GO

CREATE TABLE dbo.ProductImages (
    ImageID   INT IDENTITY(1,1) CONSTRAINT PK_ProductImages PRIMARY KEY,
    ProductID INT NOT NULL CONSTRAINT FK_PImg_Products REFERENCES dbo.Products(ProductID) ON DELETE CASCADE,
    ImageUrl  VARCHAR(300) NOT NULL,
    SortOrder INT NOT NULL CONSTRAINT DF_PImg_Sort DEFAULT 0
);
GO

-- Thông số kỹ thuật dạng key-value, phục vụ lọc & kiểm tra tương thích (socket, loại RAM, công suất...)
CREATE TABLE dbo.ProductSpecs (
    SpecID    INT IDENTITY(1,1) CONSTRAINT PK_ProductSpecs PRIMARY KEY,
    ProductID INT NOT NULL CONSTRAINT FK_PSpec_Products REFERENCES dbo.Products(ProductID) ON DELETE CASCADE,
    SpecName  NVARCHAR(100) NOT NULL,   -- vd: Socket, Loại RAM, Công suất, Dung lượng
    SpecValue NVARCHAR(200) NOT NULL,   -- vd: AM5, DDR5, 750W, 16GB
    CONSTRAINT UQ_PSpec UNIQUE (ProductID, SpecName)
);
CREATE INDEX IX_PSpec_NameValue ON dbo.ProductSpecs(SpecName, SpecValue);
GO

-- Lịch sử thay đổi giá: giá cũ, giá mới, thời điểm, người thực hiện (STT 31)
CREATE TABLE dbo.PriceHistory (
    PriceHistoryID BIGINT IDENTITY(1,1) CONSTRAINT PK_PriceHistory PRIMARY KEY,
    ProductID      INT NOT NULL CONSTRAINT FK_PH_Products REFERENCES dbo.Products(ProductID),
    OldPrice       DECIMAL(18,0) NOT NULL,
    NewPrice       DECIMAL(18,0) NOT NULL,
    ChangedBy      INT NOT NULL CONSTRAINT FK_PH_Users REFERENCES dbo.Users(UserID),
    ChangedAt      DATETIME2(0) NOT NULL CONSTRAINT DF_PH_At DEFAULT SYSDATETIME(),
    Reason         NVARCHAR(255) NULL
);
CREATE INDEX IX_PH_Product ON dbo.PriceHistory(ProductID, ChangedAt DESC);
GO

/* =====================================================================
   3. NHÓM KHO DÙNG CHUNG
   ===================================================================== */

-- Tồn kho dùng chung cho toàn hệ thống (STT 20)
CREATE TABLE dbo.Inventory (
    ProductID         INT NOT NULL CONSTRAINT PK_Inventory PRIMARY KEY
                     CONSTRAINT FK_Inv_Products REFERENCES dbo.Products(ProductID),
    Quantity          INT NOT NULL CONSTRAINT DF_Inv_Qty DEFAULT 0 CONSTRAINT CK_Inv_Qty CHECK (Quantity >= 0),
    LowStockThreshold INT NOT NULL CONSTRAINT DF_Inv_Low DEFAULT 5 CONSTRAINT CK_Inv_Low CHECK (LowStockThreshold >= 0),
    IsHidden          BIT NOT NULL CONSTRAINT DF_Inv_Hidden DEFAULT 0,
    UpdatedAt         DATETIME2(0) NOT NULL CONSTRAINT DF_Inv_Upd DEFAULT SYSDATETIME()
);
GO

-- Nhật ký biến động tồn kho, truy vết khi chỉnh sửa hoặc bán hàng
CREATE TABLE dbo.StockMovements (
    MovementID    BIGINT IDENTITY(1,1) CONSTRAINT PK_StockMovements PRIMARY KEY,
    ProductID     INT NOT NULL CONSTRAINT FK_SM_Products REFERENCES dbo.Products(ProductID),
    MovementType  VARCHAR(20) NOT NULL CONSTRAINT CK_SM_Type CHECK (MovementType IN ('Import','Sale','Cancel','Return','Adjust')),
    QuantityChange INT NOT NULL,
    RefType       VARCHAR(20) NULL,
    RefID         INT NULL,
    Note          NVARCHAR(255) NULL,
    CreatedBy     INT NULL CONSTRAINT FK_SM_Users REFERENCES dbo.Users(UserID),
    CreatedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_SM_Created DEFAULT SYSDATETIME()
);
CREATE INDEX IX_SM_Product_Created ON dbo.StockMovements(ProductID, CreatedAt DESC);
GO

/* =====================================================================
4. NHÓM GIỎ HÀNG
   ===================================================================== */

-- Giỏ hàng của Người dùng (CustomerID) hoặc giỏ tạm của Guest theo phiên (SessionToken) - STT 4, 38
CREATE TABLE dbo.Carts (
    CartID       INT IDENTITY(1,1) CONSTRAINT PK_Carts PRIMARY KEY,
    CustomerID   INT NULL CONSTRAINT FK_Carts_Customers REFERENCES dbo.Customers(CustomerID) ON DELETE CASCADE,
    SessionToken VARCHAR(100) NULL,
    CreatedAt    DATETIME2(0) NOT NULL CONSTRAINT DF_Carts_Created DEFAULT SYSDATETIME(),
    UpdatedAt    DATETIME2(0) NOT NULL CONSTRAINT DF_Carts_Upd DEFAULT SYSDATETIME(),
    CONSTRAINT CK_Carts_Owner CHECK (CustomerID IS NOT NULL OR SessionToken IS NOT NULL)
);
CREATE UNIQUE INDEX UX_Carts_Customer ON dbo.Carts(CustomerID)   WHERE CustomerID IS NOT NULL;
CREATE UNIQUE INDEX UX_Carts_Session  ON dbo.Carts(SessionToken) WHERE SessionToken IS NOT NULL;
GO
CREATE TABLE dbo.CartItems (
    CartItemID INT IDENTITY(1,1) CONSTRAINT PK_CartItems PRIMARY KEY,
    CartID     INT NOT NULL CONSTRAINT FK_CI_Carts REFERENCES dbo.Carts(CartID) ON DELETE CASCADE,
    ProductID  INT NOT NULL CONSTRAINT FK_CI_Products REFERENCES dbo.Products(ProductID),
    Quantity   INT NOT NULL CONSTRAINT CK_CI_Qty CHECK (Quantity > 0),
    AddedAt    DATETIME2(0) NOT NULL CONSTRAINT DF_CI_Added DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_CartItem UNIQUE (CartID, ProductID)
);
GO

/* =====================================================================
   5. NHÓM ĐƠN HÀNG - THANH TOÁN - HOÁ ĐƠN
   ===================================================================== */

-- Phương thức thanh toán, cấu hình bởi Admin (STT 6, 33)
CREATE TABLE dbo.PaymentMethods (
    PaymentMethodID INT IDENTITY(1,1) CONSTRAINT PK_PaymentMethods PRIMARY KEY,
    MethodCode      VARCHAR(20)  NOT NULL CONSTRAINT UQ_PM_Code UNIQUE,   -- CASH, TRANSFER, QR
    MethodName      NVARCHAR(100) NOT NULL,
    IsActive        BIT NOT NULL CONSTRAINT DF_PM_Active DEFAULT 1
);
GO

/* Đơn hàng: dùng chung cho online và offline.
   - Channel: Online (website) / Offline (bán tại quầy)
   - ReceiveMethod: Delivery (giao tận nơi) / Pickup (nhận tại cửa hàng) / InStore (mua tại quầy)
   - CustomerID NULL khi khách vãng lai mua tại quầy không để lại thông tin */
CREATE TABLE dbo.Orders (
    OrderID         INT IDENTITY(1,1) CONSTRAINT PK_Orders PRIMARY KEY,
    OrderCode       VARCHAR(30) NOT NULL CONSTRAINT UQ_Orders_Code UNIQUE,
    CustomerID      INT NULL CONSTRAINT FK_Orders_Customers REFERENCES dbo.Customers(CustomerID),
    Channel         VARCHAR(10) NOT NULL CONSTRAINT CK_Orders_Channel CHECK (Channel IN ('Online','Offline')),
    ReceiveMethod   VARCHAR(10) NOT NULL CONSTRAINT CK_Orders_Receive CHECK (ReceiveMethod IN ('Delivery','Pickup','InStore')),
    -- Thông tin giao hàng được "chụp" lại tại thời điểm đặt (không phụ thuộc sổ địa chỉ sau này)
    ReceiverName    NVARCHAR(100) NULL,
    ReceiverPhone   VARCHAR(20)   NULL,
    ShippingAddress NVARCHAR(500) NULL,
    SubTotal        DECIMAL(18,0) NOT NULL CONSTRAINT DF_Orders_Sub DEFAULT 0,
    ShippingFee     DECIMAL(18,0) NOT NULL CONSTRAINT DF_Orders_Ship DEFAULT 0,
    TotalAmount     DECIMAL(18,0) NOT NULL CONSTRAINT DF_Orders_Total DEFAULT 0,
    -- Trạng thái đơn: chờ xử lý, đã thanh toán, đang giao, hoàn thành, đã hủy (STT 8)
    Status          VARCHAR(15) NOT NULL CONSTRAINT DF_Orders_Status DEFAULT 'Pending'
                    CONSTRAINT CK_Orders_Status CHECK (Status IN ('Pending','Paid','Shipping','Completed','Cancelled')),
    PaymentStatus   VARCHAR(10) NOT NULL CONSTRAINT DF_Orders_PayStatus DEFAULT 'Unpaid'
                    CONSTRAINT CK_Orders_PayStatus CHECK (PaymentStatus IN ('Unpaid','Paid','Refunded')),
    CreatedBy       INT NULL CONSTRAINT FK_Orders_CreatedBy REFERENCES dbo.Users(UserID),  -- nhân viên lập đơn tại quầy
    HandledBy       INT NULL CONSTRAINT FK_Orders_HandledBy REFERENCES dbo.Users(UserID),  -- nhân viên/quản trị viên xử lý đơn online
    Note            NVARCHAR(500) NULL,
    CreatedAt       DATETIME2(0) NOT NULL CONSTRAINT DF_Orders_Created DEFAULT SYSDATETIME(),
    UpdatedAt       DATETIME2(0) NULL,
    CompletedAt     DATETIME2(0) NULL,
    CancelledAt     DATETIME2(0) NULL,
    CancelledBy     INT NULL CONSTRAINT FK_Orders_CancelledBy REFERENCES dbo.Users(UserID),
    CancelReason    NVARCHAR(255) NULL,
    CONSTRAINT CK_Orders_Delivery CHECK (ReceiveMethod <> 'Delivery' OR ShippingAddress IS NOT NULL),
    CONSTRAINT CK_Orders_Cancel   CHECK (Status <> 'Cancelled' OR CancelledAt IS NOT NULL)
);
CREATE INDEX IX_Orders_Customer ON dbo.Orders(CustomerID, CreatedAt DESC);
CREATE INDEX IX_Orders_Status_Created ON dbo.Orders(Status, CreatedAt DESC);
CREATE INDEX IX_Orders_Created  ON dbo.Orders(CreatedAt) INCLUDE (Channel, Status, PaymentStatus, TotalAmount);
GO

CREATE TABLE dbo.OrderDetails (
    OrderDetailID INT IDENTITY(1,1) CONSTRAINT PK_OrderDetails PRIMARY KEY,
    OrderID       INT NOT NULL CONSTRAINT FK_OD_Orders REFERENCES dbo.Orders(OrderID) ON DELETE CASCADE,
    ProductID     INT NOT NULL CONSTRAINT FK_OD_Products REFERENCES dbo.Products(ProductID),
    Quantity      INT NOT NULL CONSTRAINT CK_OD_Qty CHECK (Quantity > 0),
    UnitPrice     DECIMAL(18,0) NOT NULL CONSTRAINT CK_OD_Price CHECK (UnitPrice >= 0),  -- giá tại thời điểm bán
    WarrantyMonths INT NOT NULL CONSTRAINT DF_OD_Warranty DEFAULT 0,                      -- bảo hành áp dụng tại thời điểm bán
    LineTotal     AS (Quantity * UnitPrice) PERSISTED,
    CONSTRAINT UQ_OD UNIQUE (OrderID, ProductID)
);
CREATE INDEX IX_OD_Product ON dbo.OrderDetails(ProductID);
GO

-- Thanh toán của đơn hàng (STT 6, 13)
CREATE TABLE dbo.Payments (
    PaymentID       INT IDENTITY(1,1) CONSTRAINT PK_Payments PRIMARY KEY,
    OrderID         INT NOT NULL CONSTRAINT FK_Pay_Orders REFERENCES dbo.Orders(OrderID),
    PaymentMethodID INT NOT NULL CONSTRAINT FK_Pay_Methods REFERENCES dbo.PaymentMethods(PaymentMethodID),
    Amount          DECIMAL(18,0) NOT NULL CONSTRAINT CK_Pay_Amount CHECK (Amount > 0),
    Status          VARCHAR(10) NOT NULL CONSTRAINT DF_Pay_Status DEFAULT 'Pending'
                    CONSTRAINT CK_Pay_Status CHECK (Status IN ('Pending','Success','Failed','Refunded')),
    TransactionRef  VARCHAR(100) NULL,         -- mã giao dịch chuyển khoản / QR
    PaidAt          DATETIME2(0) NULL,
    ConfirmedBy     INT NULL CONSTRAINT FK_Pay_Users REFERENCES dbo.Users(UserID),  -- nhân viên xác nhận
    CreatedAt       DATETIME2(0) NOT NULL CONSTRAINT DF_Pay_Created DEFAULT SYSDATETIME()
);
CREATE INDEX IX_Pay_Order ON dbo.Payments(OrderID);
GO

-- Hoá đơn xuất/in cho khách (STT 14)
CREATE TABLE dbo.Invoices (
    InvoiceID   INT IDENTITY(1,1) CONSTRAINT PK_Invoices PRIMARY KEY,
    InvoiceNo   VARCHAR(30) NOT NULL CONSTRAINT UQ_Invoices_No UNIQUE,
    OrderID     INT NOT NULL CONSTRAINT UQ_Invoices_Order UNIQUE
                CONSTRAINT FK_Inv_Orders REFERENCES dbo.Orders(OrderID),
    IssuedBy    INT NOT NULL CONSTRAINT FK_Invoices_Users REFERENCES dbo.Users(UserID),
    IssuedAt    DATETIME2(0) NOT NULL CONSTRAINT DF_Invoices_At DEFAULT SYSDATETIME(),
    PrintCount  INT NOT NULL CONSTRAINT DF_Invoices_Print DEFAULT 1   -- số lần in/in lại
);
GO

/* =====================================================================
   6. NHÓM LẮP ĐẶT - BẢO HÀNH/ĐỔI TRẢ - ĐÁNH GIÁ
   ===================================================================== */

-- Phân công lắp đặt/lắp ráp máy (STT 24)
CREATE TABLE dbo.AssemblyJobs (
    JobID        INT IDENTITY(1,1) CONSTRAINT PK_AssemblyJobs PRIMARY KEY,
    OrderID      INT NOT NULL CONSTRAINT FK_AJ_Orders REFERENCES dbo.Orders(OrderID),
    AssignedTo   INT NOT NULL CONSTRAINT FK_AJ_AssignedTo REFERENCES dbo.Users(UserID),  -- nhân viên thực hiện
    AssignedBy   INT NOT NULL CONSTRAINT FK_AJ_AssignedBy REFERENCES dbo.Users(UserID),  -- quản trị viên phân công
    Status       VARCHAR(12) NOT NULL CONSTRAINT DF_AJ_Status DEFAULT 'Waiting'
                 CONSTRAINT CK_AJ_Status CHECK (Status IN ('Waiting','InProgress','Done')),
    Requirement  NVARCHAR(500) NULL,
    AssignedAt   DATETIME2(0) NOT NULL CONSTRAINT DF_AJ_At DEFAULT SYSDATETIME(),
    StartedAt    DATETIME2(0) NULL,
    FinishedAt   DATETIME2(0) NULL
);
CREATE INDEX IX_AJ_Status ON dbo.AssemblyJobs(Status);
CREATE INDEX IX_AJ_Assignee      ON dbo.AssemblyJobs(AssignedTo, Status);
GO

-- Yêu cầu bảo hành / đổi trả (STT 11, 17, 25)
CREATE TABLE dbo.WarrantyRequests (
    RequestID     INT IDENTITY(1,1) CONSTRAINT PK_WarrantyRequests PRIMARY KEY,
    RequestCode   VARCHAR(30) NOT NULL CONSTRAINT UQ_WR_Code UNIQUE,
    OrderDetailID INT NOT NULL CONSTRAINT FK_WR_OD REFERENCES dbo.OrderDetails(OrderDetailID),
    CustomerID    INT NULL CONSTRAINT FK_WR_Customers REFERENCES dbo.Customers(CustomerID),
    RequestType   VARCHAR(10) NOT NULL CONSTRAINT CK_WR_Type CHECK (RequestType IN ('Warranty','Return','Exchange')),
    Source        VARCHAR(10) NOT NULL CONSTRAINT CK_WR_Source CHECK (Source IN ('Online','Counter','Offline')),
    Quantity      INT NOT NULL CONSTRAINT DF_WR_Qty DEFAULT 1 CONSTRAINT CK_WR_Qty CHECK (Quantity > 0),
    Reason        NVARCHAR(1000) NOT NULL,
    ReceivedBy    INT NULL CONSTRAINT FK_WR_ReceivedBy REFERENCES dbo.Users(UserID),   -- nhân viên tiếp nhận tại quầy
    Status        VARCHAR(12) NOT NULL CONSTRAINT DF_WR_Status DEFAULT 'Pending'
                  CONSTRAINT CK_WR_Status CHECK (Status IN ('Pending','Processing','Completed','Rejected')),
    HandledBy     INT NULL CONSTRAINT FK_WR_HandledBy REFERENCES dbo.Users(UserID),    -- quản trị viên xử lý
    ResolutionNote NVARCHAR(1000) NULL,
    RefundApproved BIT NOT NULL CONSTRAINT DF_WR_Refund DEFAULT 0,                    -- quản trị viên duyệt hoàn tiền
    RefundAmount  DECIMAL(18,0) NULL CONSTRAINT CK_WR_RefundAmt CHECK (RefundAmount IS NULL OR RefundAmount >= 0),
    CreatedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_WR_Created DEFAULT SYSDATETIME(),
    UpdatedAt     DATETIME2(0) NULL,
    CONSTRAINT CK_WR_RefundOnlyReturn CHECK (RefundApproved = 0 OR RequestType = 'Return')
);
CREATE INDEX IX_WR_Status ON dbo.WarrantyRequests(Status);
CREATE INDEX IX_WR_Customer      ON dbo.WarrantyRequests(CustomerID);
GO
CREATE TABLE dbo.WarrantyRequestImages (
    ImageID   INT IDENTITY(1,1) CONSTRAINT PK_WRImages PRIMARY KEY,
    RequestID INT NOT NULL CONSTRAINT FK_WRI_WR REFERENCES dbo.WarrantyRequests(RequestID) ON DELETE CASCADE,
    ImageUrl  VARCHAR(300) NOT NULL
);
GO

-- Đánh giá sản phẩm: chỉ người đã mua, mỗi dòng hàng đánh giá 1 lần (STT 12)
CREATE TABLE dbo.Reviews (
    ReviewID      INT IDENTITY(1,1) CONSTRAINT PK_Reviews PRIMARY KEY,
    ProductID     INT NOT NULL CONSTRAINT FK_Rev_Products REFERENCES dbo.Products(ProductID),
    CustomerID    INT NOT NULL CONSTRAINT FK_Rev_Customers REFERENCES dbo.Customers(CustomerID),
    OrderDetailID INT NOT NULL CONSTRAINT UQ_Rev_OD UNIQUE
                  CONSTRAINT FK_Rev_OD REFERENCES dbo.OrderDetails(OrderDetailID),
    Rating        TINYINT NOT NULL CONSTRAINT CK_Rev_Rating CHECK (Rating BETWEEN 1 AND 5),
    Comment       NVARCHAR(1000) NULL,
    IsVisible     BIT NOT NULL CONSTRAINT DF_Rev_Visible DEFAULT 1,
    CreatedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_Rev_Created DEFAULT SYSDATETIME()
);
CREATE INDEX IX_Rev_Product ON dbo.Reviews(ProductID, CreatedAt DESC);
GO

/* =====================================================================
   7. NHÓM THÔNG BÁO - CHATBOT - CẤU HÌNH HỆ THỐNG
   ===================================================================== */

-- Thông báo gửi riêng cho người dùng (STT 19, 10)
CREATE TABLE dbo.Notifications (
    NotificationID BIGINT IDENTITY(1,1) CONSTRAINT PK_Notifications PRIMARY KEY,
    UserID    INT NOT NULL CONSTRAINT FK_Noti_Users REFERENCES dbo.Users(UserID),
    NotiType  VARCHAR(20) NOT NULL CONSTRAINT CK_Noti_Type
              CHECK (NotiType IN ('NewOrder','LowStock','OrderCancelled','Warranty','Admin','System')),
    Title     NVARCHAR(200) NOT NULL,
    Content   NVARCHAR(1000) NULL,
    RefType   VARCHAR(20) NULL,
    RefID     INT NULL,
    IsRead    BIT NOT NULL CONSTRAINT DF_Noti_Read DEFAULT 0,
    CreatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_Noti_Created DEFAULT SYSDATETIME()
);
CREATE INDEX IX_Noti_User ON dbo.Notifications(UserID, IsRead, CreatedAt DESC);
GO

-- Nội dung trả lời cố định của chatbot do Admin quản lý (STT 33)
CREATE TABLE dbo.ChatbotFAQ (
    FaqID     INT IDENTITY(1,1) CONSTRAINT PK_ChatbotFAQ PRIMARY KEY,
    Topic     VARCHAR(20) NOT NULL CONSTRAINT CK_FAQ_Topic CHECK (Topic IN ('Price','Stock','Warranty','Return','Other')),
    Keywords  NVARCHAR(300) NOT NULL,
    Answer    NVARCHAR(2000) NOT NULL,
    IsActive  BIT NOT NULL CONSTRAINT DF_FAQ_Active DEFAULT 1,
    UpdatedBy INT NULL CONSTRAINT FK_FAQ_Users REFERENCES dbo.Users(UserID),
    UpdatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_FAQ_Upd DEFAULT SYSDATETIME()
);
GO

-- Lịch sử hội thoại chatbot (cả Guest qua SessionToken và Người dùng) - STT 7, 37
CREATE TABLE dbo.ChatSessions (
    ChatSessionID INT IDENTITY(1,1) CONSTRAINT PK_ChatSessions PRIMARY KEY,
    CustomerID    INT NULL CONSTRAINT FK_CS_Customers REFERENCES dbo.Customers(CustomerID),
    SessionToken  VARCHAR(100) NULL,
    StartedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_CS_Start DEFAULT SYSDATETIME()
);
GO
CREATE TABLE dbo.ChatMessages (
    MessageID     BIGINT IDENTITY(1,1) CONSTRAINT PK_ChatMessages PRIMARY KEY,
    ChatSessionID INT NOT NULL CONSTRAINT FK_CM_CS REFERENCES dbo.ChatSessions(ChatSessionID) ON DELETE CASCADE,
    Sender        VARCHAR(10) NOT NULL CONSTRAINT CK_CM_Sender CHECK (Sender IN ('User','Bot')),
    Content       NVARCHAR(MAX) NOT NULL,
    CreatedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_CM_Created DEFAULT SYSDATETIME()
);
CREATE INDEX IX_CM_Session ON dbo.ChatMessages(ChatSessionID, CreatedAt);
GO

-- Cấu hình hệ thống dạng key-value: phí vận chuyển, ... (STT 33)
CREATE TABLE dbo.SystemSettings (
    SettingKey   VARCHAR(100) NOT NULL CONSTRAINT PK_SystemSettings PRIMARY KEY,
    SettingValue NVARCHAR(500) NOT NULL,
    Description  NVARCHAR(255) NULL,
    UpdatedBy    INT NULL CONSTRAINT FK_SS_Users REFERENCES dbo.Users(UserID),
    UpdatedAt    DATETIME2(0) NOT NULL CONSTRAINT DF_SS_Upd DEFAULT SYSDATETIME()
);
GO

-- Chính sách bảo hành / đổi trả áp dụng toàn hệ thống (STT 33)
CREATE TABLE dbo.Policies (
    PolicyID   INT IDENTITY(1,1) CONSTRAINT PK_Policies PRIMARY KEY,
    PolicyType VARCHAR(10) NOT NULL CONSTRAINT CK_Policy_Type CHECK (PolicyType IN ('Warranty','Return')),
    Title      NVARCHAR(200) NOT NULL,
    Content    NVARCHAR(MAX) NOT NULL,
    IsActive   BIT NOT NULL CONSTRAINT DF_Policy_Active DEFAULT 1,
    UpdatedBy  INT NULL CONSTRAINT FK_Policy_Users REFERENCES dbo.Users(UserID),
    UpdatedAt  DATETIME2(0) NOT NULL CONSTRAINT DF_Policy_Upd DEFAULT SYSDATETIME()
);
GO

/* =====================================================================
   8. VIEW BÁO CÁO / TRA CỨU
   ===================================================================== */

-- Sản phẩm + tồn kho dùng chung (khách xem tình trạng còn hàng, STT 3, 36)
CREATE VIEW dbo.vw_ProductStock AS
SELECT p.ProductID, p.SKU, p.ProductName, c.CategoryName, b.BrandName, p.Price,
       p.WarrantyMonths, p.Status, i.Quantity,
       CASE WHEN i.Quantity > 0 THEN 1 ELSE 0 END AS InStock,
       i.IsHidden
FROM dbo.Products p
JOIN dbo.Categories c ON c.CategoryID = p.CategoryID
JOIN dbo.Brands b     ON b.BrandID    = p.BrandID
LEFT JOIN dbo.Inventory i ON i.ProductID = p.ProductID;
GO

-- Sản phẩm sắp hết hàng (STT 19, 20)
CREATE VIEW dbo.vw_LowStock AS
SELECT p.ProductID, p.SKU, p.ProductName, i.Quantity, i.LowStockThreshold
FROM dbo.Inventory i
JOIN dbo.Products p ON p.ProductID = i.ProductID
WHERE i.Quantity <= i.LowStockThreshold AND i.IsHidden = 0 AND p.Status = 'Active';
GO

-- Điểm đánh giá trung bình theo sản phẩm
CREATE VIEW dbo.vw_ProductRating AS
SELECT ProductID, COUNT(*) AS ReviewCount, CAST(AVG(CAST(Rating AS DECIMAL(4,2))) AS DECIMAL(3,2)) AS AvgRating
FROM dbo.Reviews
WHERE IsVisible = 1
GROUP BY ProductID;
GO

-- Doanh thu theo ngày và kênh (tính đơn đã thanh toán, không bị hủy) - STT 22, 32
CREATE VIEW dbo.vw_DailyRevenue AS
SELECT CAST(o.CreatedAt AS DATE) AS RevenueDate,
       o.Channel,
       COUNT(*)            AS OrderCount,
       SUM(o.TotalAmount)  AS Revenue
FROM dbo.Orders o
WHERE o.Status <> 'Cancelled' AND o.PaymentStatus = 'Paid'
GROUP BY CAST(o.CreatedAt AS DATE), o.Channel;
GO

-- Sản phẩm bán chạy (STT 22)
CREATE VIEW dbo.vw_BestSellers AS
SELECT od.ProductID, p.ProductName,
       SUM(od.Quantity) AS QuantitySold,
       SUM(od.LineTotal) AS Revenue
FROM dbo.OrderDetails od
JOIN dbo.Orders o   ON o.OrderID = od.OrderID
JOIN dbo.Products p ON p.ProductID = od.ProductID
WHERE o.Status <> 'Cancelled' AND o.PaymentStatus = 'Paid'
GROUP BY od.ProductID, p.ProductName;
GO

-- Doanh thu theo nhân viên lập đơn (STT 22)
CREATE VIEW dbo.vw_StaffRevenue AS
SELECT o.CreatedBy AS StaffID, u.FullName AS StaffName,
       COUNT(*) AS OrderCount, SUM(o.TotalAmount) AS Revenue
FROM dbo.Orders o
JOIN dbo.Users u ON u.UserID = o.CreatedBy
WHERE o.Status <> 'Cancelled' AND o.PaymentStatus = 'Paid'
GROUP BY o.CreatedBy, u.FullName;
GO

/* =====================================================================
9. STORED PROCEDURE: ĐIỀU CHỈNH GIÁ HÀNG LOẠT (STT 31)
   Mode = 'PERCENT' (tăng/giảm theo %) hoặc 'AMOUNT' (tăng/giảm theo số tiền, giá trị âm = giảm).
   Có thể lọc theo danh mục và/hoặc thương hiệu; tự ghi lịch sử giá.
   ===================================================================== */
CREATE PROCEDURE dbo.sp_BulkAdjustPrice
    @CategoryID INT = NULL,
    @BrandID    INT = NULL,
    @Mode       VARCHAR(10),
    @Value      DECIMAL(18,2),
    @ChangedBy  INT,
    @Reason     NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Mode NOT IN ('PERCENT','AMOUNT')
        THROW 50001, N'Mode phải là PERCENT hoặc AMOUNT.', 1;

    DECLARE @Changes TABLE (ProductID INT, OldPrice DECIMAL(18,0), NewPrice DECIMAL(18,0));

    BEGIN TRAN;

    UPDATE p
       SET p.Price     = x.NewPrice,
           p.UpdatedAt = SYSDATETIME()
    OUTPUT inserted.ProductID, deleted.Price, inserted.Price INTO @Changes
    FROM dbo.Products p
    CROSS APPLY (
        SELECT CASE WHEN calc.v < 0 THEN 0 ELSE calc.v END AS NewPrice
        FROM (SELECT CAST(ROUND(CASE WHEN @Mode = 'PERCENT'
                                     THEN p.Price * (1 + @Value / 100.0)
                                     ELSE p.Price + @Value END, 0) AS DECIMAL(18,0)) AS v) calc
    ) x
    WHERE (@CategoryID IS NULL OR p.CategoryID = @CategoryID)
      AND (@BrandID    IS NULL OR p.BrandID    = @BrandID)
      AND p.Status <> 'Discontinued'
      AND x.NewPrice <> p.Price;

    INSERT INTO dbo.PriceHistory (ProductID, OldPrice, NewPrice, ChangedBy, Reason)
    SELECT ProductID, OldPrice, NewPrice, @ChangedBy, @Reason FROM @Changes;

    COMMIT;

    SELECT COUNT(*) AS ProductsUpdated FROM @Changes;
END;
GO


/* =====================================================================
   10. DU LIEU MAU (SEED DATA) - CORETCH
   Tuong thich voi dung cau truc bang trong file schema nay.
   Chay tren database moi sau khi tao xong cac bang / stored procedures.
   ===================================================================== */
USE ShopLinhKienMayTinh;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- Vai tro
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleCode='Admin')
 INSERT dbo.Roles(RoleCode,RoleName,Description) VALUES
 ('Admin',N'Quản trị viên',N'Quản trị toàn hệ thống');
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleCode='Staff')
 INSERT dbo.Roles(RoleCode,RoleName,Description) VALUES
 ('Staff',N'Nhân viên',N'Nhân viên bán hàng và kho');
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleCode='Customer')
 INSERT dbo.Roles(RoleCode,RoleName,Description) VALUES
 ('Customer',N'Khách hàng',N'Khách hàng website');

-- Tài khoản mẫu: Admin, Staff, Customer
-- Mật khẩu demo lần lượt: Admin@123, Staff@123, Customer@123
-- PasswordHash tương thích PBKDF2WithHmacSHA256 của PasswordUtil.
INSERT dbo.Users (RoleID, FullName, Email, Phone, PasswordHash, IsVerified, IsActive)
SELECT r.RoleID, v.FullName, v.Email, v.Phone, v.PasswordHash, 1, 1
FROM (VALUES
    ('Admin', N'Quản trị viên CoreTech', 'admin@coretech.local', '0900000001', '65536:12sgUZZNONImxsfws+THEg==:TCpiC7CkbINz7N1atvv6P/YC3jMM5v5wkVeaOH6z8Lc='),
    ('Staff', N'Nhân viên CoreTech', 'staff@coretech.local', '0900000003', '65536:seFqKphhbx9JS+A9aJmAxg==:h2yr3+aTLYmO35dOy+bkajYYjG/LLIA3yC8a/apbUXc='),
    ('Customer', N'Khách hàng mẫu', 'customer@coretech.local', '0900000004', '65536:ukb3gl/n5cKAFwbuHpojTw==:XF6oHHa5FIYcBjvuY/dzDVYU4IKm41znA/3SCRr3M0M=')
) v(RoleCode, FullName, Email, Phone, PasswordHash)
JOIN dbo.Roles r ON r.RoleCode = v.RoleCode
WHERE NOT EXISTS (SELECT 1 FROM dbo.Users u WHERE u.Email = v.Email);

-- Danh muc
INSERT dbo.Categories(CategoryName,Description)
SELECT v.CategoryName,v.Description
FROM (VALUES
 (N'Bộ vi xử lý (CPU)',N'Bộ vi xử lý Intel và AMD'),
 (N'Card đồ họa (GPU)',N'Card đồ họa chơi game và đồ họa'),
 (N'Bo mạch chủ (Mainboard)',N'Bo mạch chủ Intel và AMD'),
 (N'Bộ nhớ RAM',N'RAM DDR4 và DDR5'),
 (N'Ổ cứng SSD',N'Ổ cứng SATA và NVMe'),
 (N'Nguồn máy tính (PSU)',N'Bộ nguồn máy tính'),
 (N'Thùng máy (Case)',N'Vỏ máy tính'),
 (N'Tản nhiệt',N'Tản nhiệt khí và tản nhiệt nước')
) v(CategoryName,Description)
WHERE NOT EXISTS(SELECT 1 FROM dbo.Categories c WHERE c.CategoryName=v.CategoryName);

-- Thuong hieu
INSERT dbo.Brands(BrandName,LogoUrl)
SELECT v.BrandName,v.LogoUrl
FROM (VALUES
 (N'Intel','https://placehold.co/240x120?text=Intel'),
 (N'AMD','https://placehold.co/240x120?text=AMD'),
 (N'ASUS','https://placehold.co/240x120?text=ASUS'),
 (N'MSI','https://placehold.co/240x120?text=MSI'),
 (N'Gigabyte','https://placehold.co/240x120?text=Gigabyte'),
 (N'Kingston','https://placehold.co/240x120?text=Kingston'),
 (N'Samsung','https://placehold.co/240x120?text=Samsung'),
 (N'Corsair','https://placehold.co/240x120?text=Corsair'),
 (N'DeepCool','https://placehold.co/240x120?text=DeepCool')
) v(BrandName,LogoUrl)
WHERE NOT EXISTS(SELECT 1 FROM dbo.Brands b WHERE b.BrandName=v.BrandName);

-- San pham (SKU dung de tranh chen trung khi chay lai)
DECLARE @P TABLE(
 SKU VARCHAR(50), ProductName NVARCHAR(250), CategoryName NVARCHAR(100),
 BrandName NVARCHAR(100), Price DECIMAL(18,0), WarrantyMonths INT,
 ThumbnailUrl VARCHAR(300), Description NVARCHAR(500)
);
INSERT @P VALUES
('CPU-I5-14400F',N'Intel Core i5-14400F',N'Bộ vi xử lý (CPU)',N'Intel',4590000,36,'https://placehold.co/600x600/111827/e5e7eb?text=Intel+i5',N'CPU Intel Core i5 thế hệ 14, phù hợp chơi game và làm việc.'),
('CPU-I7-14700K',N'Intel Core i7-14700K',N'Bộ vi xử lý (CPU)',N'Intel',9990000,36,'https://placehold.co/600x600/111827/e5e7eb?text=Intel+i7',N'CPU hiệu năng cao cho chơi game và sáng tạo nội dung.'),
('CPU-R5-7600',N'AMD Ryzen 5 7600',N'Bộ vi xử lý (CPU)',N'AMD',5290000,36,'https://placehold.co/600x600/111827/e5e7eb?text=Ryzen+5',N'CPU AMD Ryzen socket AM5.'),
('GPU-RTX4060-8G',N'ASUS Dual GeForce RTX 4060 8GB',N'Card đồ họa (GPU)',N'ASUS',8290000,36,'https://placehold.co/600x600/111827/e5e7eb?text=RTX+4060',N'Card đồ họa NVIDIA GeForce RTX 4060 8GB.'),
('GPU-RTX4070S-12G',N'MSI GeForce RTX 4070 SUPER 12GB',N'Card đồ họa (GPU)',N'MSI',16990000,36,'https://placehold.co/600x600/111827/e5e7eb?text=RTX+4070+SUPER',N'GPU hiệu năng cao cho chơi game độ phân giải cao.'),
('GPU-RX7600-8G',N'Gigabyte Radeon RX 7600 8GB',N'Card đồ họa (GPU)',N'Gigabyte',6990000,36,'https://placehold.co/600x600/111827/e5e7eb?text=RX+7600',N'Card đồ họa AMD Radeon RX 7600 8GB.'),
('MB-B760M-TUF',N'ASUS TUF Gaming B760M-PLUS WIFI',N'Bo mạch chủ (Mainboard)',N'ASUS',4690000,36,'https://placehold.co/600x600/111827/e5e7eb?text=B760M',N'Mainboard Intel B760 hỗ trợ DDR5 và Wi-Fi.'),
('MB-B650M-PRO',N'MSI PRO B650M-A WIFI',N'Bo mạch chủ (Mainboard)',N'MSI',4290000,36,'https://placehold.co/600x600/111827/e5e7eb?text=B650M',N'Mainboard AMD B650 socket AM5.'),
('RAM-KF5600-16',N'Kingston Fury Beast DDR5 16GB 5600MHz',N'Bộ nhớ RAM',N'Kingston',1390000,120,'https://placehold.co/600x600/111827/e5e7eb?text=DDR5+16GB',N'RAM DDR5 16GB tốc độ 5600MHz.'),
('RAM-COR-32',N'Corsair Vengeance DDR5 32GB 6000MHz',N'Bộ nhớ RAM',N'Corsair',2890000,120,'https://placehold.co/600x600/111827/e5e7eb?text=DDR5+32GB',N'RAM DDR5 32GB tốc độ 6000MHz.'),
('SSD-SAM-990-1T',N'Samsung 990 PRO NVMe 1TB',N'Ổ cứng SSD',N'Samsung',2890000,60,'https://placehold.co/600x600/111827/e5e7eb?text=Samsung+990+PRO',N'SSD NVMe PCIe 4.0 dung lượng 1TB.'),
('SSD-KC3000-2T',N'Kingston KC3000 NVMe 2TB',N'Ổ cứng SSD',N'Kingston',4290000,60,'https://placehold.co/600x600/111827/e5e7eb?text=Kingston+KC3000',N'SSD NVMe PCIe 4.0 dung lượng 2TB.'),
('PSU-CV650',N'Corsair CV650 650W 80 Plus Bronze',N'Nguồn máy tính (PSU)',N'Corsair',1290000,36,'https://placehold.co/600x600/111827/e5e7eb?text=PSU+650W',N'Nguồn 650W chứng nhận 80 Plus Bronze.'),
('CASE-MSI-110R',N'MSI MAG Forge 110R',N'Thùng máy (Case)',N'MSI',1190000,12,'https://placehold.co/600x600/111827/e5e7eb?text=MSI+Case',N'Case gaming mặt kính cường lực, quạt RGB.'),
('COOL-DC-AS500',N'DeepCool AS500',N'Tản nhiệt',N'DeepCool',1490000,24,'https://placehold.co/600x600/111827/e5e7eb?text=CPU+Cooler',N'Tản nhiệt khí dạng tower cho CPU.'),
('RAM-KF432-16',N'Kingston Fury Beast DDR4 16GB 3200MHz',N'Bộ nhớ RAM',N'Kingston',890000,120,'https://placehold.co/600x600/111827/e5e7eb?text=DDR4+16GB',N'RAM DDR4 16GB tốc độ 3200MHz.');

INSERT dbo.Products(SKU,ProductName,CategoryID,BrandID,Description,Price,WarrantyMonths,ThumbnailUrl,Status)
SELECT s.SKU,s.ProductName,c.CategoryID,b.BrandID,s.Description,s.Price,s.WarrantyMonths,s.ThumbnailUrl,'Active'
FROM @P s
JOIN dbo.Categories c ON c.CategoryName=s.CategoryName
JOIN dbo.Brands b ON b.BrandName=s.BrandName
WHERE NOT EXISTS(SELECT 1 FROM dbo.Products p WHERE p.SKU=s.SKU);

-- Anh san pham
INSERT dbo.ProductImages(ProductID,ImageUrl,SortOrder)
SELECT p.ProductID,p.ThumbnailUrl,1
FROM dbo.Products p JOIN @P s ON s.SKU=p.SKU
WHERE p.ThumbnailUrl IS NOT NULL
AND NOT EXISTS(SELECT 1 FROM dbo.ProductImages i WHERE i.ProductID=p.ProductID AND i.ImageUrl=p.ThumbnailUrl);

-- Thong so ky thuat
INSERT dbo.ProductSpecs(ProductID,SpecName,SpecValue)
SELECT p.ProductID,v.SpecName,v.SpecValue
FROM (VALUES
 ('CPU-I5-14400F',N'Socket',N'LGA1700'),('CPU-I5-14400F',N'Số nhân / luồng',N'10 nhân / 16 luồng'),
 ('CPU-I7-14700K',N'Socket',N'LGA1700'),('CPU-R5-7600',N'Socket',N'AM5'),
 ('GPU-RTX4060-8G',N'VRAM',N'8GB GDDR6'),('GPU-RTX4070S-12G',N'VRAM',N'12GB GDDR6X'),
 ('GPU-RX7600-8G',N'VRAM',N'8GB GDDR6'),('MB-B760M-TUF',N'Chipset',N'Intel B760'),
 ('MB-B650M-PRO',N'Chipset',N'AMD B650'),('RAM-KF5600-16',N'Dung lượng',N'16GB DDR5 5600MHz'),
 ('RAM-COR-32',N'Dung lượng',N'32GB DDR5 6000MHz'),('SSD-SAM-990-1T',N'Dung lượng',N'1TB NVMe PCIe 4.0'),
 ('SSD-KC3000-2T',N'Dung lượng',N'2TB NVMe PCIe 4.0'),('PSU-CV650',N'Công suất',N'650W'),
 ('RAM-KF432-16',N'Dung lượng',N'16GB DDR4 3200MHz')
) v(SKU,SpecName,SpecValue)
JOIN dbo.Products p ON p.SKU=v.SKU
WHERE NOT EXISTS(SELECT 1 FROM dbo.ProductSpecs x WHERE x.ProductID=p.ProductID AND x.SpecName=v.SpecName);

-- Tồn kho dùng chung
INSERT dbo.Inventory(ProductID, Quantity, LowStockThreshold, IsHidden)
SELECT p.ProductID, 18, 5, 0
FROM dbo.Products p
JOIN @P s ON s.SKU = p.SKU
WHERE NOT EXISTS (SELECT 1 FROM dbo.Inventory i WHERE i.ProductID = p.ProductID);

-- Phuong thuc thanh toan
INSERT dbo.PaymentMethods(MethodCode,MethodName)
SELECT v.MethodCode,v.MethodName
FROM (VALUES ('CASH',N'Tiền mặt'),('TRANSFER',N'Chuyển khoản ngân hàng'),('QR',N'Thanh toán QR')) v(MethodCode,MethodName)
WHERE NOT EXISTS(SELECT 1 FROM dbo.PaymentMethods p WHERE p.MethodCode=v.MethodCode);

-- FAQ chatbot
INSERT dbo.ChatbotFAQ(Topic,Keywords,Answer)
SELECT v.Topic,v.Keywords,v.Answer
FROM (VALUES
 ('Warranty',N'bảo hành;thời gian bảo hành',N'Thời hạn bảo hành được hiển thị trong thông tin từng sản phẩm. Vui lòng giữ hóa đơn khi yêu cầu bảo hành.'),
 ('Return',N'đổi trả;trả hàng',N'Vui lòng liên hệ cửa hàng và cung cấp mã đơn hàng để được hướng dẫn đổi trả.'),
 ('Stock',N'kiểm tra tồn kho;còn hàng',N'Bạn có thể xem số lượng hàng còn trong thông tin từng sản phẩm.'),
 ('Other',N'thanh toán;chuyển khoản',N'CoreTech hỗ trợ tiền mặt, chuyển khoản và QR theo phương thức hiển thị khi đặt hàng.')
) v(Topic,Keywords,Answer)
WHERE NOT EXISTS(SELECT 1 FROM dbo.ChatbotFAQ f WHERE f.Keywords=v.Keywords);

-- Cau hinh
INSERT dbo.SystemSettings(SettingKey,SettingValue,Description)
SELECT v.SettingKey,v.SettingValue,v.Description
FROM (VALUES
 ('SHIPPING_FEE',N'30000',N'Phí giao hàng mặc định (VNĐ)'),
 ('FREE_SHIPPING_MIN',N'2000000',N'Giá trị đơn tối thiểu miễn phí giao hàng (VNĐ)'),
 ('STORE_NAME',N'CoreTech',N'Tên cửa hàng hiển thị trên website')
) v(SettingKey,SettingValue,Description)
WHERE NOT EXISTS(SELECT 1 FROM dbo.SystemSettings s WHERE s.SettingKey=v.SettingKey);

-- Chinh sach
INSERT dbo.Policies(PolicyType,Title,Content)
SELECT v.PolicyType,v.Title,v.Content
FROM (VALUES
 ('Warranty',N'Chính sách bảo hành mẫu',N'Thời hạn bảo hành áp dụng theo từng sản phẩm. Khách hàng cần cung cấp hóa đơn hoặc thông tin đơn hàng khi yêu cầu bảo hành.'),
 ('Return',N'Chính sách đổi trả mẫu',N'Sản phẩm đổi trả cần đáp ứng điều kiện tiếp nhận của cửa hàng. Vui lòng liên hệ nhân viên để được kiểm tra tình trạng sản phẩm.')
) v(PolicyType,Title,Content)
WHERE NOT EXISTS(SELECT 1 FROM dbo.Policies p WHERE p.PolicyType=v.PolicyType AND p.Title=v.Title);

COMMIT TRANSACTION;
GO

PRINT N'Đã thêm dữ liệu mẫu CoreTech thành công.';
SELECT N'Danh mục' AS Bang,COUNT(*) AS SoLuong FROM dbo.Categories
UNION ALL SELECT N'Thương hiệu',COUNT(*) FROM dbo.Brands
UNION ALL SELECT N'Sản phẩm',COUNT(*) FROM dbo.Products
UNION ALL SELECT N'Ảnh sản phẩm',COUNT(*) FROM dbo.ProductImages
UNION ALL SELECT N'Thông số',COUNT(*) FROM dbo.ProductSpecs
UNION ALL SELECT N'Tồn kho',COUNT(*) FROM dbo.Inventory
UNION ALL SELECT N'Phương thức thanh toán',COUNT(*) FROM dbo.PaymentMethods;
GO
/* =====================================================================
   BỔ SUNG CSDL cho khớp Model Java (Branches, Suppliers, GoodsReceipts,
   BranchInventory, cột BranchID...). Chạy lại nhiều lần vẫn an toàn.
   Chạy SAU file ShopLinhKienMayTinh.sql.
   ===================================================================== */
USE ShopLinhKienMayTinh;
GO

-- 1. Vai trò Manager (AuthFilter có /manager)
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleCode='Manager')
    INSERT dbo.Roles(RoleCode,RoleName,Description) VALUES ('Manager',N'Quản lý chi nhánh',N'Quản lý kho và nhân viên của chi nhánh');
GO

-- 2. Chi nhánh
IF OBJECT_ID('dbo.Branches') IS NULL
CREATE TABLE dbo.Branches (
    BranchID      INT IDENTITY(1,1) CONSTRAINT PK_Branches PRIMARY KEY,
    BranchName    NVARCHAR(150) NOT NULL,
    Address       NVARCHAR(300) NOT NULL,
    Phone         VARCHAR(20) NULL,
    ManagerUserID INT NULL CONSTRAINT FK_Branch_Manager REFERENCES dbo.Users(UserID),
    IsActive      BIT NOT NULL CONSTRAINT DF_Branch_Active DEFAULT 1,
    CreatedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_Branch_Created DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.Branches)
    INSERT dbo.Branches(BranchName,Address,Phone) VALUES (N'CoreTech - Chi nhánh 1',N'Quận 1, TP.HCM','0281234567');
GO

-- 3. Thêm cột BranchID vào các bảng Java đang dùng
DECLARE @t TABLE(n SYSNAME);
INSERT @t VALUES ('Users'),('Orders'),('StockMovements'),('AssemblyJobs'),('WarrantyRequests'),('Notifications');
DECLARE @n SYSNAME;
DECLARE c CURSOR FOR SELECT n FROM @t;
OPEN c; FETCH NEXT FROM c INTO @n;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF COL_LENGTH('dbo.'+@n,'BranchID') IS NULL
        EXEC('ALTER TABLE dbo.'+@n+' ADD BranchID INT NULL CONSTRAINT FK_'+@n+'_Branch REFERENCES dbo.Branches(BranchID)');
    FETCH NEXT FROM c INTO @n;
END
CLOSE c; DEALLOCATE c;
GO

-- 4. Gán dữ liệu cũ về chi nhánh đầu tiên (Admin và Customer giữ NULL)
DECLARE @b INT = (SELECT MIN(BranchID) FROM dbo.Branches);
UPDATE dbo.Orders           SET BranchID=@b WHERE BranchID IS NULL;
UPDATE dbo.StockMovements   SET BranchID=@b WHERE BranchID IS NULL;
UPDATE dbo.AssemblyJobs     SET BranchID=@b WHERE BranchID IS NULL;
UPDATE dbo.WarrantyRequests SET BranchID=@b WHERE BranchID IS NULL;
UPDATE u SET u.BranchID=@b FROM dbo.Users u JOIN dbo.Roles r ON r.RoleID=u.RoleID
WHERE r.RoleCode IN ('Staff','Manager') AND u.BranchID IS NULL;
GO

-- 5. Tồn kho theo chi nhánh (chuyển dữ liệu từ bảng Inventory cũ)
IF OBJECT_ID('dbo.BranchInventory') IS NULL
BEGIN
    CREATE TABLE dbo.BranchInventory (
        BranchID          INT NOT NULL CONSTRAINT FK_BI_Branch REFERENCES dbo.Branches(BranchID),
        ProductID         INT NOT NULL CONSTRAINT FK_BI_Product REFERENCES dbo.Products(ProductID),
        Quantity          INT NOT NULL CONSTRAINT DF_BI_Qty DEFAULT 0 CONSTRAINT CK_BI_Qty CHECK (Quantity >= 0),
        LowStockThreshold INT NOT NULL CONSTRAINT DF_BI_Low DEFAULT 5 CONSTRAINT CK_BI_Low CHECK (LowStockThreshold >= 0),
        IsHidden          BIT NOT NULL CONSTRAINT DF_BI_Hidden DEFAULT 0,
        UpdatedAt         DATETIME2(0) NOT NULL CONSTRAINT DF_BI_Upd DEFAULT SYSDATETIME(),
        CONSTRAINT PK_BranchInventory PRIMARY KEY (BranchID, ProductID)
    );
    EXEC('INSERT dbo.BranchInventory(BranchID,ProductID,Quantity,LowStockThreshold,IsHidden)
          SELECT (SELECT MIN(BranchID) FROM dbo.Branches), ProductID, Quantity, LowStockThreshold, IsHidden FROM dbo.Inventory');
END
GO

-- 6. Nhà cung cấp
IF OBJECT_ID('dbo.Suppliers') IS NULL
CREATE TABLE dbo.Suppliers (
    SupplierID   INT IDENTITY(1,1) CONSTRAINT PK_Suppliers PRIMARY KEY,
    BranchID     INT NULL CONSTRAINT FK_Sup_Branch REFERENCES dbo.Branches(BranchID),  -- NULL = dùng chung
    SupplierName NVARCHAR(150) NOT NULL,
    Address      NVARCHAR(300) NULL,
    Phone        VARCHAR(20) NULL,
    Email        VARCHAR(150) NULL,
    IsActive     BIT NOT NULL CONSTRAINT DF_Sup_Active DEFAULT 1,
    CreatedAt    DATETIME2(0) NOT NULL CONSTRAINT DF_Sup_Created DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.Suppliers)
    INSERT dbo.Suppliers(SupplierName,Address,Phone,Email) VALUES
    (N'Công ty TNHH Phong Vũ',N'Quận 3, TP.HCM','0287654321','sales@phongvu.local'),
    (N'Công ty CP Hoàng Hà',N'Quận Tân Bình, TP.HCM','0289876543','info@hoangha.local');
GO

-- 7. Phiếu nhập hàng
IF OBJECT_ID('dbo.GoodsReceipts') IS NULL
CREATE TABLE dbo.GoodsReceipts (
    ReceiptID    INT IDENTITY(1,1) CONSTRAINT PK_GoodsReceipts PRIMARY KEY,
    ReceiptCode  VARCHAR(30) NOT NULL CONSTRAINT UQ_GR_Code UNIQUE,
    BranchID     INT NOT NULL CONSTRAINT FK_GR_Branch REFERENCES dbo.Branches(BranchID),
    SupplierID   INT NOT NULL CONSTRAINT FK_GR_Supplier REFERENCES dbo.Suppliers(SupplierID),
    CreatedBy    INT NOT NULL CONSTRAINT FK_GR_User REFERENCES dbo.Users(UserID),
    ReceiptDate  DATETIME2(0) NOT NULL CONSTRAINT DF_GR_Date DEFAULT SYSDATETIME(),
    TotalAmount  DECIMAL(18,0) NOT NULL CONSTRAINT DF_GR_Total DEFAULT 0,
    Note         NVARCHAR(500) NULL
);
GO
IF OBJECT_ID('dbo.GoodsReceiptDetails') IS NULL
CREATE TABLE dbo.GoodsReceiptDetails (
    ReceiptDetailID INT IDENTITY(1,1) CONSTRAINT PK_GRD PRIMARY KEY,
    ReceiptID       INT NOT NULL CONSTRAINT FK_GRD_Receipt REFERENCES dbo.GoodsReceipts(ReceiptID) ON DELETE CASCADE,
    ProductID       INT NOT NULL CONSTRAINT FK_GRD_Product REFERENCES dbo.Products(ProductID),
    Quantity        INT NOT NULL CONSTRAINT CK_GRD_Qty CHECK (Quantity > 0),
    ImportPrice     DECIMAL(18,0) NOT NULL CONSTRAINT CK_GRD_Price CHECK (ImportPrice >= 0),
    LineTotal       AS (Quantity * ImportPrice) PERSISTED
);
GO

-- Nhật ký hệ thống (STT 32). Bỏ file này nếu bảng AuditLogs đã có sẵn trên máy.
IF OBJECT_ID('dbo.AuditLogs') IS NULL
CREATE TABLE dbo.AuditLogs (
    AuditID    BIGINT IDENTITY(1,1) CONSTRAINT PK_AuditLogs PRIMARY KEY,
    UserID     INT NULL CONSTRAINT FK_Audit_User REFERENCES dbo.Users(UserID),
    Action     VARCHAR(30)  NOT NULL,      -- Create | Update | Delete | Login ...
    EntityType VARCHAR(50)  NOT NULL,      -- GoodsReceipt, Product, ...
    EntityID   VARCHAR(50)  NULL,
    Detail     NVARCHAR(500) NULL,
    CreatedAt  DATETIME2(0) NOT NULL CONSTRAINT DF_Audit_Created DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Audit_Created')
    CREATE INDEX IX_Audit_Created ON dbo.AuditLogs(CreatedAt DESC);
GO-- Nhật ký hệ thống (STT 32). Bỏ file này nếu bảng AuditLogs đã có sẵn trên máy.
IF OBJECT_ID('dbo.AuditLogs') IS NULL
CREATE TABLE dbo.AuditLogs (
    AuditID    BIGINT IDENTITY(1,1) CONSTRAINT PK_AuditLogs PRIMARY KEY,
    UserID     INT NULL CONSTRAINT FK_Audit_User REFERENCES dbo.Users(UserID),
    Action     VARCHAR(30)  NOT NULL,      -- Create | Update | Delete | Login ...
    EntityType VARCHAR(50)  NOT NULL,      -- GoodsReceipt, Product, ...
    EntityID   VARCHAR(50)  NULL,
    Detail     NVARCHAR(500) NULL,
    CreatedAt  DATETIME2(0) NOT NULL CONSTRAINT DF_Audit_Created DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Audit_Created')
    CREATE INDEX IX_Audit_Created ON dbo.AuditLogs(CreatedAt DESC);
GO

-- Nhật ký hệ thống (STT 32). Bỏ file này nếu bảng AuditLogs đã có sẵn trên máy.
IF OBJECT_ID('dbo.AuditLogs') IS NULL
CREATE TABLE dbo.AuditLogs (
    AuditID    BIGINT IDENTITY(1,1) CONSTRAINT PK_AuditLogs PRIMARY KEY,
    UserID     INT NULL CONSTRAINT FK_Audit_User REFERENCES dbo.Users(UserID),
    Action     VARCHAR(30)  NOT NULL,      -- Create | Update | Delete | Login ...
    EntityType VARCHAR(50)  NOT NULL,      -- GoodsReceipt, Product, ...
    EntityID   VARCHAR(50)  NULL,
    Detail     NVARCHAR(500) NULL,
    CreatedAt  DATETIME2(0) NOT NULL CONSTRAINT DF_Audit_Created DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Audit_Created')
    CREATE INDEX IX_Audit_Created ON dbo.AuditLogs(CreatedAt DESC);
GO