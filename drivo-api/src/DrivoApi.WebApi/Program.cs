using System.Text.Json.Serialization;
﻿using DrivoApi.Application.Services;
using DrivoApi.Application.Settings;
using DrivoApi.Infrastructure;
using DrivoApi.Infrastructure.Data;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

//
builder.Services.AddDbContext<DrivoDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

// JWT Settings
builder.Services.Configure<JwtSettings>(builder.Configuration.GetSection("JwtSettings"));

//  JWT Auth
var jwtSettings = builder.Configuration.GetSection("JwtSettings");
var secretKey = jwtSettings["SecretKey"]!;

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtSettings["Issuer"],
            ValidAudience = jwtSettings["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey)),
            ClockSkew = TimeSpan.Zero
        };

        // Support JWT from SignalR query string
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var accessToken = context.Request.Query["access_token"];
                var path = context.HttpContext.Request.Path;
                if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs"))
                    context.Token = accessToken;
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();

// SignalR
builder.Services.AddSignalR();

// CORS (Permissive for development & testing Web App)
builder.Services.AddCors(options =>
{
    options.AddPolicy("DrivoCors", policy =>
        policy.SetIsOriginAllowed(origin => true) // Cho phép tất cả các domain
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials());
});

// Controllers + Swagger
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
    });
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Application Services
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IAdminDriverService, AdminDriverService>();
builder.Services.AddScoped<IDriverProfileService, DriverProfileService>();
builder.Services.AddScoped<ICustomerVehicleService, CustomerVehicleService>();
builder.Services.AddScoped<IBookingService, BookingService>();
// TODO Nguyen Nhat: builder.Services.AddScoped<IBookingService, BookingService>();
// TODO Nguyen Nhat: builder.Services.AddScoped<IPaymentService, PaymentService>();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("DrivoCors");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// SignalR Hubs
// app.MapHub<TrackingHub>("/hubs/tracking");

app.Run();

